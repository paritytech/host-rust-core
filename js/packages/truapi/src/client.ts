import { errAsync, okAsync, ResultAsync } from "neverthrow";

import {
  decodeWireMessage,
  encodeWireMessage,
  MIN_TRAIT_ID,
  PROTOCOL_ERROR_METHOD_ID,
  PROTOCOL_ERROR_TRAIT_ID,
  type HostInitiatedSubscriptionHandler,
  type ObservableSource,
  type ProtocolMessage,
  type RegisterHostInitiatedSubscriptionParams,
  type RequestFrameIds,
  type RequestParams,
  type SubscriptionFrameIds,
  type SubscribeRawParams,
  type Subscription,
  type TrUApiTransport,
  type UnsupportedCallError,
  UnsupportedMessageError,
  type WireProvider,
} from "./transport.js";
import {
  CallError,
  indexedTaggedUnion,
  Result,
  _void,
  type CallErrorValue,
  type Codec,
  type ResultPayload,
} from "./scale.js";
import { TRUAPI_CODEC_VERSION } from "./generated/client.js";
import * as T from "./generated/types.js";
import * as W from "./generated/wire-table.js";

export type { Subscription, TrUApiTransport };

const UNANSWERED_WIRE_IDS = new Set<string>(
  Object.values(W).flatMap((ids) =>
    "response" in ids
      ? [`${ids.trait}:${ids.response}`]
      : [
          `${ids.trait}:${ids.stop}`,
          `${ids.trait}:${ids.interrupt}`,
          `${ids.trait}:${ids.receive}`,
        ],
  ),
);

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
 * Convert a positive protocol version number into the generated version tag
 * used by TrUAPI wire wrappers.
 */
function protocolVersionTag(version: number): `V${number}` {
  if (!Number.isInteger(version) || version < 1) {
    throw new Error(`Invalid TrUAPI protocol version: ${version}`);
  }
  return `V${version}` as `V${number}`;
}

type HandshakeResponse = ResultPayload<
  undefined,
  CallErrorValue<T.VersionedHostHandshakeError>
>;
const HANDSHAKE_WIRE_VERSION = 1;

/**
 * How long a `system_handshake` call waits for the host's answer. Matches the
 * allowance the protocol spec gives the handshake.
 */
const HANDSHAKE_TIMEOUT_MS = 10_000;

/**
 * Build the versioned handshake response codec for the selected wire version.
 */
function handshakeResponseCodec(
  version: number,
): Codec<{ tag: `V${number}`; value: HandshakeResponse }> {
  return indexedTaggedUnion({
    [protocolVersionTag(version)]: [
      version - 1,
      Result(_void, CallError(T.VersionedHostHandshakeError)),
    ] as const,
  }) as Codec<{ tag: `V${number}`; value: HandshakeResponse }>;
}

/**
 * Encode a successful host-handshake response payload.
 */
function encodeSuccessfulHandshakeResponse(version: number): Uint8Array {
  return encodeHandshakeResponse(version, {
    tag: protocolVersionTag(version),
    value: {
      success: true,
      value: undefined,
    },
  });
}

/**
 * Encode a host-handshake response that reports an unsupported codec version.
 */
function encodeUnsupportedHandshakeResponse(version: number): Uint8Array {
  return encodeHandshakeResponse(version, {
    tag: protocolVersionTag(version),
    value: {
      success: false,
      value: {
        tag: "Domain",
        value: {
          tag: "V1",
          value: {
            tag: "UnsupportedProtocolVersion",
            value: undefined,
          },
        },
      },
    },
  });
}

/**
 * Encode a typed handshake response with the versioned response codec.
 */
function encodeHandshakeResponse(
  version: number,
  response: { tag: `V${number}`; value: HandshakeResponse },
): Uint8Array {
  return handshakeResponseCodec(version).enc(response);
}

type VersionedWireValue = { tag: `V${number}`; value: unknown };

/**
 * Check whether a decoded SCALE value has the generated `{ tag, value }`
 * wrapper shape used for versioned wire payloads.
 */
function isVersionedWireValue(value: unknown): value is VersionedWireValue {
  return (
    typeof value === "object" &&
    value !== null &&
    "tag" in value &&
    "value" in value &&
    typeof value.tag === "string" &&
    /^V\d+$/.test(value.tag)
  );
}

/**
 * Return the inner payload from a versioned wire wrapper, or the original
 * value when the payload is already unwrapped.
 */
function unwrapVersionedWireValue(value: unknown): unknown {
  return isVersionedWireValue(value) ? value.value : value;
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
      ids: RequestFrameIds;
      resolve: (value: Uint8Array) => void;
      resolveUnsupported: () => void;
      reject: (error: Error) => void;
    }
  >();
  const subscriptions = new Map<
    string,
    {
      ids: SubscriptionFrameIds;
      onReceive: (payload: Uint8Array) => void;
      onInterrupt?: (payload: Uint8Array) => void;
      onClose?: (error: Error) => void;
    }
  >();
  type BufferedHostStart = { requestId: string; payload: Uint8Array };
  type HostRoute = {
    ids: SubscriptionFrameIds;
    decodeRequest: (payload: Uint8Array) => unknown;
    encodeItem: (item: unknown) => Uint8Array;
    interruptPayload: Uint8Array;
    bufferCapacity: number;
    buffered: BufferedHostStart[];
    handler?: (request: unknown) => ObservableSource<unknown>;
    instances: Map<string, { unsubscribe(): void }>;
  };
  // Keyed by the full (trait, method) start pair: a bare start id would
  // collide the moment two traits both number a subscription the same.
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
        request?.ids.request === unsupported.methodId
      ) {
        pending.delete(requestId);
        request.resolveUnsupported();
        return;
      }

      const subscription = subscriptions.get(requestId);
      if (
        subscription?.ids.trait === unsupported.traitId &&
        subscription?.ids.start === unsupported.methodId
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
      payload.methodId === W.SYSTEM_HANDSHAKE.request
    ) {
      // Auto-respond to inbound `host_handshake_request` frames. Hosts ping
      // the product at startup and repeat until they see a matching response,
      // so this handler must always answer and must never tear the transport
      // down: a host whose codec this client cannot speak is exactly the peer
      // that needs an answer it can act on.
      //
      // Respond with the handshake method's selected wire version. The inner
      // request carries the wire codec version. A request body this client
      // cannot decode is itself a codec mismatch -- a codec 1 host's frame
      // reads as `(0, 0)` here with the old envelope's payload shifted by a
      // byte -- so it earns the same unsupported-version answer rather than a
      // raw SCALE error.
      let response: Uint8Array;
      try {
        const request = unwrapVersionedWireValue(
          T.VersionedHostHandshakeRequest.dec(payload.value),
        ) as T.HostHandshakeRequest;
        const requestedCodecVersion = request.codecVersion;
        response =
          requestedCodecVersion === codecVersion
            ? encodeSuccessfulHandshakeResponse(HANDSHAKE_WIRE_VERSION)
            : encodeUnsupportedHandshakeResponse(HANDSHAKE_WIRE_VERSION);
      } catch (error) {
        reportProtocolViolation(
          `undecodable handshake request from the host (expected wire codec ${codecVersion}): ${
            toError(error).message
          }`,
        );
        response = encodeUnsupportedHandshakeResponse(HANDSHAKE_WIRE_VERSION);
      }
      try {
        send({
          requestId,
          payload: {
            traitId: W.SYSTEM_HANDSHAKE.trait,
            methodId: W.SYSTEM_HANDSHAKE.response,
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
      startHostSubscription(hostRoute, requestId, payload.value);
      return;
    }
    for (const candidate of hostRoutes.values()) {
      if (
        payload.traitId !== candidate.ids.trait ||
        payload.methodId !== candidate.ids.stop
      )
        continue;
      const bufferedIndex = candidate.buffered.findIndex(
        (start) => start.requestId === requestId,
      );
      if (bufferedIndex >= 0) candidate.buffered.splice(bufferedIndex, 1);
      const instance = candidate.instances.get(requestId);
      if (instance) {
        candidate.instances.delete(requestId);
        instance.unsubscribe();
      }
      return;
    }

    const p = pending.get(requestId);
    if (p) {
      if (
        payload.traitId !== p.ids.trait ||
        payload.methodId !== p.ids.response
      ) {
        // The host answered this request id on a discriminant the method does
        // not own. Dropping it unreported leaves the caller waiting forever
        // with no clue why, and a whole-trait skew is what a codec mismatch
        // looks like from here.
        //
        // Report it, then fall through rather than returning: the request stays
        // pending (this frame is not its answer), and the frame itself is one
        // this build cannot route, so it earns the same protocol-error reply as
        // any other unroutable pair. A known client-bound pair is still filtered
        // out by `UNANSWERED_WIRE_IDS` below.
        reportProtocolViolation(
          `ignoring frame for request ${requestId}: got discriminant (${payload.traitId}, ${payload.methodId}), expected (${p.ids.trait}, ${p.ids.response})`,
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
        payload.methodId === subscription.ids.receive
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
        payload.methodId === subscription.ids.interrupt
      ) {
        subscriptions.delete(requestId);
        subscription.onInterrupt?.(payload.value);
      } else {
        reportProtocolViolation(
          `ignoring frame for subscription ${requestId}: got discriminant (${payload.traitId}, ${payload.methodId}), expected receive (${subscription.ids.trait}, ${subscription.ids.receive}) or interrupt (${subscription.ids.trait}, ${subscription.ids.interrupt})`,
        );
      }
      return;
    }

    if (UNANSWERED_WIRE_IDS.has(`${payload.traitId}:${payload.methodId}`)) {
      return;
    }

    // Not pending, no subscription, and not a client-bound frame we ignore by
    // design: this build does not implement the pair.
    reportProtocolViolation(
      `unsupported frame with discriminant (${payload.traitId}, ${payload.methodId}): request ${requestId} is not pending and has no subscription`,
    );
    // Answer only a peer that could read the answer. A trait byte below the
    // floor is not a trait at all - it is a codec 1 peer's flat method id - and
    // such a peer would read our `(255, 255)` reply as codec 1 discriminant 255
    // with a payload it cannot decode, and tear its own transport down over a
    // malformed-protocol-error that says nothing about the real problem. The
    // log above is the diagnostic for that case.
    if (payload.traitId < MIN_TRAIT_ID) {
      return;
    }
    try {
      send({
        requestId,
        payload: {
          traitId: PROTOCOL_ERROR_TRAIT_ID,
          methodId: PROTOCOL_ERROR_METHOD_ID,
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
          methodId: route.ids.interrupt,
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
                methodId: route.ids.receive,
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
          ids.request === W.SYSTEM_HANDSHAKE.request
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
              methodId: ids.request,
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
            methodId: ids.start,
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
                methodId: ids.stop,
                value: _void.enc(undefined),
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
      const key = pairKey(ids.trait, ids.start);
      if (hostRoutes.has(key)) {
        throw new Error(
          `host-initiated subscription (${ids.trait}, ${ids.start}) is already registered`,
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
