import { errAsync, okAsync, ResultAsync } from "neverthrow";

import {
  decodeWireMessage,
  encodeWireMessage,
  MESSAGE_TYPE_INTERRUPT,
  MESSAGE_TYPE_RECEIVE,
  MESSAGE_TYPE_REQUEST,
  MESSAGE_TYPE_RESPONSE,
  MESSAGE_TYPE_START,
  MESSAGE_TYPE_STOP,
  PROTOCOL_ERROR_METHOD_ID,
  PROTOCOL_ERROR_TRAIT_ID,
  type HostInitiatedSubscriptionHandler,
  type MethodIds,
  type ObservableSource,
  type ProtocolMessage,
  type RegisterHostInitiatedSubscriptionParams,
  type RequestParams,
  type SubscribeRawParams,
  type Subscription,
  type TrUApiTransport,
  type UnsupportedCallError,
  UnsupportedMessageError,
  type WireProvider,
} from "./transport.js";
import * as S from "./scale.js";
import { type ResultPayload } from "./scale.js";
import { TRUAPI_CODEC_VERSION } from "./generated/client.js";
import * as T from "./generated/types.js";
import * as W from "./generated/wire-table.js";

export type { Subscription, TrUApiTransport };

// Every method's request/response (or start/stop/interrupt/receive) frames
// share one (trait, method) address: which leg of the exchange a frame
// carries is the wire's own `messageType` byte, not part of the address. A
// late or duplicate *answer*-leg frame (Response/Stop/Interrupt/Receive) for
// a known method can legitimately arrive with no matching pending call or
// subscription (e.g. after a request already timed out, or after
// `unsubscribe`), so those are ignored rather than reported as a protocol
// violation. A *request*-leg frame (Request/Start) with nothing to route to
// is never expected — it means this build genuinely doesn't implement the
// pair (no client was ever created, or the specific host-initiated method
// has no registration) — so it still earns the same reply as an unknown
// pair.
const KNOWN_WIRE_IDS = new Set<string>(
  Object.values(W).map((ids) => `${ids.trait}:${ids.method}`),
);

/** A subscription cancellation: `Stop` carries no payload at all. **/
const STOP_FRAME = new Uint8Array();

/**
 * Version overrides used when constructing a transport.
 */
export interface CreateTransportOptions {
  /**
   * SCALE codec version advertised during host handshake negotiation.
   *
   * @deprecated TODO(shared-core-wire): remove this override with
   * `TrUApiTransport.codecVersion` once generated handshake requests use
   * `TRUAPI_CODEC_VERSION` directly.
   */
  codecVersion?: number;
}

/**
 * Report a frame the transport received but cannot act on.
 *
 * Every such frame is a disagreement with the peer about the wire, and the
 * transport has no channel to answer on: the caller is left waiting and
 * "the host dropped it" is indistinguishable from "the host never sent it".
 * Warn so the mismatch is diagnosable from the console instead of presenting
 * as an unexplained hang.
 */
function reportProtocolViolation(detail: string): void {
  console.warn(`[truapi] ${detail}`);
}

/**
 * How long a `system_handshake` call waits for the host's answer. Matches the
 * allowance the protocol spec gives the handshake.
 */
const HANDSHAKE_TIMEOUT_MS = 10_000;

/**
 * Codec for `system_handshake`'s `Response`-leg payload:
 * `Result<HostHandshakeResponse, CallError<HostHandshakeError>>`.
 */
const HANDSHAKE_RESPONSE_CODEC = S.Result(
  T.VersionedHostHandshakeResponse,
  S.CallError(T.VersionedHostHandshakeError),
);

/**
 * Encode a successful host-handshake response frame:
 * `Ok(HostHandshakeResponse::V1)`.
 */
function encodeSuccessfulHandshakeResponse(): Uint8Array {
  return HANDSHAKE_RESPONSE_CODEC.enc({
    success: true,
    value: { tag: "V1" },
  });
}

/**
 * Encode a host-handshake response frame reporting an unsupported codec
 * version: `Err(CallError::Domain(HostHandshakeError::V1(
 * UnsupportedProtocolVersion)))`.
 */
function encodeUnsupportedHandshakeResponse(): Uint8Array {
  return HANDSHAKE_RESPONSE_CODEC.enc({
    success: false,
    value: {
      tag: "Domain",
      value: {
        tag: "V1",
        value: { tag: "UnsupportedProtocolVersion", value: undefined },
      },
    },
  });
}

/**
 * Map key for a `(trait, method)` wire discriminant pair. Both bytes together
 * identify a frame, so neither half alone is a usable key.
 */
function pairKey(traitId: number, methodId: number): string {
  return `${traitId}:${methodId}`;
}

/**
 * Decode `V1(UnsupportedMessage { trait_id, method_id })`. Codec 2 addresses a
 * frame by a pair, so the payload is four bytes: version index, error variant
 * index, then the trait and method of the frame the peer could not handle.
 */
function decodeUnsupportedMessage(payload: Uint8Array): {
  traitId: number;
  methodId: number;
} {
  if (payload.length !== 4) {
    throw new Error(
      `Malformed protocol error payload: expected 4 bytes, received ${payload.length}`,
    );
  }
  if (payload[0] !== 0) {
    throw new Error(
      `Malformed protocol error payload: unsupported version ${payload[0]}`,
    );
  }
  if (payload[1] !== 0) {
    throw new Error(
      `Malformed protocol error payload: unknown error discriminant ${payload[1]}`,
    );
  }
  return { traitId: payload[2], methodId: payload[3] };
}

/**
 * Build a `TrUApiTransport` on top of a `WireProvider`, adding request/response
 * correlation and subscription start/receive/stop lifecycle handling.
 */
export function createTransport(
  provider: WireProvider,
  options: CreateTransportOptions = {},
): TrUApiTransport {
  const codecVersion = options.codecVersion ?? TRUAPI_CODEC_VERSION;
  let idCounter = 0;
  let closedError: Error | null = null;
  const pending = new Map<
    string,
    {
      ids: MethodIds;
      resolve: (value: Uint8Array) => void;
      resolveUnsupported: () => void;
      reject: (error: Error) => void;
    }
  >();
  const subscriptions = new Map<
    string,
    {
      ids: MethodIds;
      onReceive: (payload: Uint8Array) => void;
      onInterrupt?: (payload: Uint8Array) => void;
      onClose?: (error: Error) => void;
    }
  >();
  type BufferedHostStart = { requestId: string; payload: Uint8Array };
  type HostRoute = {
    ids: MethodIds;
    decodeRequest: (payload: Uint8Array) => unknown;
    encodeItem: (item: unknown) => Uint8Array;
    interruptPayload: Uint8Array;
    bufferCapacity: number;
    buffered: BufferedHostStart[];
    handler?: (request: unknown) => ObservableSource<unknown>;
    instances: Map<string, { unsubscribe(): void }>;
  };
  // Keyed by the full (trait, method) pair: a bare method id would collide
  // the moment two traits both number a subscription the same.
  const hostRoutes = new Map<string, HostRoute>();

  /**
   * Normalize arbitrary thrown values into `Error` instances.
   */
  function toError(error: unknown): Error {
    return error instanceof Error ? error : new Error(String(error));
  }

  /**
   * Close the transport once, rejecting pending requests and notifying live
   * subscriptions.
   */
  function closeWithError(error: unknown) {
    const nextError = toError(error);
    if (closedError) {
      return;
    }

    closedError = nextError;

    for (const [requestId, entry] of pending) {
      pending.delete(requestId);
      entry.reject(nextError);
    }

    for (const [requestId, subscription] of subscriptions) {
      subscriptions.delete(requestId);
      subscription.onClose?.(nextError);
    }

    for (const route of hostRoutes.values()) {
      route.buffered.length = 0;
      for (const instance of route.instances.values()) instance.unsubscribe();
      route.instances.clear();
    }
  }

  const unsubscribeClose = provider.subscribeClose?.((error) => {
    closeWithError(error);
  });

  const unsubscribeMessage = provider.subscribe((message) => {
    if (closedError) {
      return;
    }

    const decoded = decodeWireMessage(message);
    if (decoded.isErr()) {
      closeWithError(decoded.error);
      return;
    }
    const { requestId, payload } = decoded.value;

    if (
      payload.traitId === PROTOCOL_ERROR_TRAIT_ID &&
      payload.methodId === PROTOCOL_ERROR_METHOD_ID
    ) {
      let unsupported: { traitId: number; methodId: number };
      try {
        unsupported = decodeUnsupportedMessage(payload.value);
      } catch (error) {
        closeWithError(error);
        return;
      }

      // Match on the whole pair: a bare method id would alias across traits and
      // could resolve the wrong pending call.
      const request = pending.get(requestId);
      if (
        request?.ids.trait === unsupported.traitId &&
        request?.ids.method === unsupported.methodId
      ) {
        pending.delete(requestId);
        request.resolveUnsupported();
        return;
      }

      const subscription = subscriptions.get(requestId);
      if (
        subscription?.ids.trait === unsupported.traitId &&
        subscription?.ids.method === unsupported.methodId
      ) {
        subscriptions.delete(requestId);
        subscription.onClose?.(
          new UnsupportedMessageError(
            unsupported.traitId,
            unsupported.methodId,
          ),
        );
      }
      return;
    }

    if (
      payload.traitId === W.SYSTEM_HANDSHAKE.trait &&
      payload.methodId === W.SYSTEM_HANDSHAKE.method &&
      payload.messageType === MESSAGE_TYPE_REQUEST
    ) {
      // Auto-respond to inbound `host_handshake_request` frames. Hosts ping
      // the product at startup and repeat until they see a matching response,
      // so this handler must always answer and must never tear the transport
      // down: a host whose codec this client cannot speak is exactly the peer
      // that needs an answer it can act on.
      //
      // The messageType check above matters: request and response now share
      // this address, and a `Response` frame arriving here is the host's
      // answer to this client's own `system.handshake()` call, which must
      // fall through to the `pending` lookup below instead.
      //
      // Respond with the handshake method's selected wire version. The inner
      // request carries the wire codec version. A request body this client
      // cannot decode is itself a codec mismatch, so it earns the same
      // unsupported-version answer rather than a raw SCALE error.
      let response: Uint8Array;
      try {
        const request = T.VersionedHostHandshakeRequest.dec(payload.value);
        const requestedCodecVersion = request.value.codecVersion;
        response =
          requestedCodecVersion === codecVersion
            ? encodeSuccessfulHandshakeResponse()
            : encodeUnsupportedHandshakeResponse();
      } catch (error) {
        reportProtocolViolation(
          `undecodable handshake request from the host (expected wire codec ${codecVersion}): ${
            toError(error).message
          }`,
        );
        response = encodeUnsupportedHandshakeResponse();
      }
      try {
        send({
          requestId,
          payload: {
            traitId: W.SYSTEM_HANDSHAKE.trait,
            methodId: W.SYSTEM_HANDSHAKE.method,
            messageType: MESSAGE_TYPE_RESPONSE,
            value: response,
          },
        });
      } catch {
        // provider already closed
      }
      return;
    }

    const hostRoute = hostRoutes.get(
      pairKey(payload.traitId, payload.methodId),
    );
    if (hostRoute) {
      if (payload.messageType === MESSAGE_TYPE_START) {
        startHostSubscription(hostRoute, requestId, payload.value);
      } else if (payload.messageType === MESSAGE_TYPE_STOP) {
        const bufferedIndex = hostRoute.buffered.findIndex(
          (start) => start.requestId === requestId,
        );
        if (bufferedIndex >= 0) hostRoute.buffered.splice(bufferedIndex, 1);
        const instance = hostRoute.instances.get(requestId);
        if (instance) {
          hostRoute.instances.delete(requestId);
          instance.unsubscribe();
        }
      } else {
        reportProtocolViolation(
          `ignoring host-initiated frame for (${payload.traitId}, ${payload.methodId}): unexpected messageType ${payload.messageType}, expected Start (${MESSAGE_TYPE_START}) or Stop (${MESSAGE_TYPE_STOP})`,
        );
      }
      return;
    }

    const p = pending.get(requestId);
    if (p) {
      if (payload.traitId !== p.ids.trait || payload.methodId !== p.ids.method) {
        // The host answered this request id on a discriminant the method does
        // not own. Dropping it unreported leaves the caller waiting forever
        // with no clue why, and a whole-trait skew is what a codec mismatch
        // looks like from here.
        //
        // Report it, then fall through rather than returning: the request stays
        // pending (this frame is not its answer), and the frame itself is one
        // this build cannot route, so it earns the same protocol-error reply as
        // any other unroutable pair. A known method's answer-leg frame is
        // still filtered out below.
        reportProtocolViolation(
          `ignoring frame for request ${requestId}: got discriminant (${payload.traitId}, ${payload.methodId}), expected (${p.ids.trait}, ${p.ids.method})`,
        );
      } else {
        pending.delete(requestId);
        try {
          p.resolve(payload.value);
        } catch (error) {
          p.reject(toError(error));
        }
        return;
      }
    }

    const subscription = subscriptions.get(requestId);
    if (subscription) {
      if (
        payload.traitId === subscription.ids.trait &&
        payload.methodId === subscription.ids.method &&
        payload.messageType === MESSAGE_TYPE_RECEIVE
      ) {
        try {
          subscription.onReceive(payload.value);
        } catch (error) {
          // A consumer-side decode/handler error must not tear down the
          // provider's message loop and silently break every other
          // subscription on the same transport. Surface via onClose and
          // drop this subscription; siblings stay alive.
          subscriptions.delete(requestId);
          subscription.onClose?.(toError(error));
        }
      } else if (
        payload.traitId === subscription.ids.trait &&
        payload.methodId === subscription.ids.method &&
        payload.messageType === MESSAGE_TYPE_INTERRUPT
      ) {
        subscriptions.delete(requestId);
        subscription.onInterrupt?.(payload.value);
      } else {
        reportProtocolViolation(
          `ignoring frame for subscription ${requestId}: got discriminant (${payload.traitId}, ${payload.methodId}) messageType ${payload.messageType}, expected receive (${MESSAGE_TYPE_RECEIVE}) or interrupt (${MESSAGE_TYPE_INTERRUPT}) on (${subscription.ids.trait}, ${subscription.ids.method})`,
        );
      }
      return;
    }

    if (KNOWN_WIRE_IDS.has(`${payload.traitId}:${payload.methodId}`)) {
      if (
        payload.messageType === MESSAGE_TYPE_STOP ||
        payload.messageType === MESSAGE_TYPE_INTERRUPT ||
        payload.messageType === MESSAGE_TYPE_RECEIVE
      ) {
        // A known method's answer-leg frame (Response/Stop/Interrupt/
        // Receive) with nothing to route to: a normal late/stale frame, not
        // a protocol violation.
        return;
      }
      if (payload.messageType !== MESSAGE_TYPE_REQUEST) {
        // Neither a plausible late answer nor a valid Request/Start: the
        // messageType byte itself is out of range. Still dropped (there is
        // nothing to route it to), but logged rather than silently
        // swallowed, matching the analogous case in the `hostRoute` branch
        // above.
        reportProtocolViolation(
          `ignoring frame for known pair (${payload.traitId}, ${payload.methodId}): unexpected messageType ${payload.messageType}`,
        );
        return;
      }
    }

    // Either an unknown pair, or a known method's request-leg frame
    // (Request/Start) with nothing to route to: this build does not
    // implement the pair.
    reportProtocolViolation(
      `unsupported frame with discriminant (${payload.traitId}, ${payload.methodId}): request ${requestId} is not pending and has no subscription`,
    );
    try {
      send({
        requestId,
        payload: {
          traitId: PROTOCOL_ERROR_TRAIT_ID,
          methodId: PROTOCOL_ERROR_METHOD_ID,
          messageType: MESSAGE_TYPE_RESPONSE,
          value: new Uint8Array([0, 0, payload.traitId, payload.methodId]),
        },
      });
    } catch {
      // provider already closed
    }
  });

  /**
   * Encode and post a protocol message through the underlying provider.
   */
  function send(message: ProtocolMessage) {
    if (closedError) {
      throw closedError;
    }

    const encoded = encodeWireMessage(message);
    if (encoded.isErr()) {
      closeWithError(encoded.error);
      throw encoded.error;
    }

    try {
      provider.postMessage(encoded.value);
    } catch (error) {
      closeWithError(error);
      throw toError(error);
    }
  }

  function interruptHostSubscription(route: HostRoute, requestId: string) {
    const instance = route.instances.get(requestId);
    if (instance) {
      route.instances.delete(requestId);
      instance.unsubscribe();
    }
    try {
      send({
        requestId,
        payload: {
          traitId: route.ids.trait,
          methodId: route.ids.method,
          messageType: MESSAGE_TYPE_INTERRUPT,
          value: route.interruptPayload,
        },
      });
    } catch {
      // provider already closed
    }
  }

  function startHostSubscription(
    route: HostRoute,
    requestId: string,
    payload: Uint8Array,
  ) {
    const previous = route.instances.get(requestId);
    if (previous) {
      route.instances.delete(requestId);
      previous.unsubscribe();
    }

    const handler = route.handler;
    if (!handler) {
      if (route.buffered.length === route.bufferCapacity) {
        const evicted = route.buffered.shift();
        if (evicted) interruptHostSubscription(route, evicted.requestId);
      }
      route.buffered.push({ requestId, payload });
      return;
    }

    let source: ObservableSource<unknown>;
    try {
      source = handler(route.decodeRequest(payload));
    } catch {
      interruptHostSubscription(route, requestId);
      return;
    }

    let active = true;
    let sourceSubscription: { unsubscribe(): void } | undefined;
    const instance = {
      unsubscribe() {
        if (!active) return;
        active = false;
        sourceSubscription?.unsubscribe();
      },
    };
    route.instances.set(requestId, instance);
    try {
      sourceSubscription = source.subscribe({
        next(item) {
          if (!active) return;
          try {
            send({
              requestId,
              payload: {
                traitId: route.ids.trait,
                methodId: route.ids.method,
                messageType: MESSAGE_TYPE_RECEIVE,
                value: route.encodeItem(item),
              },
            });
          } catch {
            interruptHostSubscription(route, requestId);
          }
        },
        error() {
          if (active) interruptHostSubscription(route, requestId);
        },
        // Completion deliberately keeps the instance alive and its last tree
        // on screen until the host sends `_stop`.
        complete() {},
      });
      if (!active) sourceSubscription.unsubscribe();
    } catch {
      interruptHostSubscription(route, requestId);
    }
  }

  return {
    codecVersion,
    /**
     * Send one request frame and resolve with the typed Ok/Err outcome
     * decoded from the response payload's `ResultPayload` envelope.
     */
    request<Ok, Err>({
      ids,
      payload,
      decodeResponse,
    }: RequestParams<Ok, Err>): ResultAsync<Ok, Err | UnsupportedCallError> {
      const promise = new Promise<
        ResultPayload<Ok, Err | UnsupportedCallError>
      >((resolve, reject) => {
        if (closedError) {
          reject(closedError);
          return;
        }

        const requestId = `p:${++idCounter}`;
        // The handshake is the one method with a bounded answer: it takes no
        // host-side confirmation and settles the codec question before any
        // real traffic. A peer that implements the protocol error now answers a
        // discriminant it does not know, which settles this call as
        // `Unsupported`; the deadline covers the peer that answers NOTHING -
        // an older host, or one whose codec skew leaves the frame unroutable -
        // so the call that exists to detect the mismatch cannot hang on it.
        const deadline =
          ids.trait === W.SYSTEM_HANDSHAKE.trait &&
          ids.method === W.SYSTEM_HANDSHAKE.method
            ? setTimeout(() => {
                if (!pending.delete(requestId)) {
                  return;
                }
                reject(
                  new Error(
                    `TrUAPI handshake timed out after ${HANDSHAKE_TIMEOUT_MS}ms; the host did not answer on wire codec ${codecVersion}`,
                  ),
                );
              }, HANDSHAKE_TIMEOUT_MS)
            : undefined;

        pending.set(requestId, {
          ids,
          resolve: (response) => {
            clearTimeout(deadline);
            resolve(decodeResponse(response));
          },
          // Clears the deadline like the other two: an explicit `Unsupported`
          // settles the call, and leaving the timer armed holds the event loop
          // open for the rest of the timeout for nothing.
          resolveUnsupported: () => {
            clearTimeout(deadline);
            resolve({
              success: false,
              value: { tag: "Unsupported" },
            });
          },
          reject: (error) => {
            clearTimeout(deadline);
            reject(error);
          },
        });
        try {
          send({
            requestId,
            payload: {
              traitId: ids.trait,
              methodId: ids.method,
              messageType: MESSAGE_TYPE_REQUEST,
              value: payload,
            },
          });
        } catch (error) {
          pending.delete(requestId);
          reject(toError(error));
        }
      });
      return ResultAsync.fromSafePromise(promise).andThen(
        (result): ResultAsync<Ok, Err | UnsupportedCallError> =>
          result.success ? okAsync(result.value) : errAsync(result.value),
      );
    },
    /**
     * Start a raw subscription and route incoming receive/interrupt frames to
     * the supplied callbacks.
     */
    subscribeRaw({
      ids,
      payload,
      onReceive,
      onInterrupt,
      onClose,
    }: SubscribeRawParams) {
      if (closedError) {
        onClose?.(closedError);
        return { unsubscribe: () => {}, subscriptionId: "" };
      }

      const requestId = `p:${++idCounter}`;
      subscriptions.set(requestId, {
        ids,
        onReceive,
        onInterrupt,
        onClose,
      });
      try {
        send({
          requestId,
          payload: {
            traitId: ids.trait,
            methodId: ids.method,
            messageType: MESSAGE_TYPE_START,
            value: payload,
          },
        });
      } catch (error) {
        subscriptions.delete(requestId);
        onClose?.(toError(error));
        return { unsubscribe: () => {}, subscriptionId: requestId };
      }
      return {
        subscriptionId: requestId,
        unsubscribe: () => {
          // Skip the `_stop` frame when the host already terminated the stream
          // via `_interrupt` (which removes the entry from `subscriptions`).
          if (!subscriptions.has(requestId)) return;
          subscriptions.delete(requestId);
          try {
            send({
              requestId,
              payload: {
                traitId: ids.trait,
                methodId: ids.method,
                messageType: MESSAGE_TYPE_STOP,
                value: STOP_FRAME,
              },
            });
          } catch {
            // provider already closed
          }
        },
      };
    },
    registerHostInitiatedSubscription<Request, Item>({
      ids,
      decodeRequest,
      encodeItem,
      interruptPayload,
      bufferCapacity,
    }: RegisterHostInitiatedSubscriptionParams<Request, Item>) {
      const key = pairKey(ids.trait, ids.method);
      if (hostRoutes.has(key)) {
        throw new Error(
          `host-initiated subscription (${ids.trait}, ${ids.method}) is already registered`,
        );
      }
      const route: HostRoute = {
        ids,
        decodeRequest: decodeRequest as (payload: Uint8Array) => unknown,
        encodeItem: encodeItem as (item: unknown) => Uint8Array,
        interruptPayload,
        bufferCapacity,
        buffered: [],
        instances: new Map(),
      };
      hostRoutes.set(key, route);
      return {
        setHandler(handler: HostInitiatedSubscriptionHandler<Request, Item>) {
          const installed = handler as (
            request: unknown,
          ) => ObservableSource<unknown>;
          route.handler = installed;
          for (const start of route.buffered.splice(0)) {
            startHostSubscription(route, start.requestId, start.payload);
          }
          return {
            unsubscribe() {
              if (route.handler === installed) route.handler = undefined;
            },
          };
        },
      };
    },
    /**
     * Close this transport and detach its provider listeners.
     */
    dispose() {
      // Idempotent: closeWithError is a no-op once closedError is set, and
      // unsubscribe handles tolerate being called twice.
      closeWithError(new Error("transport disposed"));
      unsubscribeMessage();
      unsubscribeClose?.();
    },
  };
}
