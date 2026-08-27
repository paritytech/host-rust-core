import { errAsync, okAsync, ResultAsync } from "neverthrow";

import {
  decodeWireMessage,
  encodeWireMessage,
  type HostInitiatedSubscriptionHandler,
  type ObservableSource,
  type ProtocolMessage,
  type RegisterHostInitiatedSubscriptionParams,
  type RequestFrameIds,
  RequestTimeoutError,
  type RequestParams,
  type SubscriptionFrameIds,
  type SubscribeRawParams,
  type Subscription,
  type TrUApiTransport,
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

  /**
   * Bound applied to every request issued through this transport, in
   * milliseconds. Must be an integer between 1 and 2147483647; there is no
   * value that disables the bound. Defaults to `DEFAULT_REQUEST_TIMEOUT_MS`.
   * Methods the host answers more slowly take the larger of this bound and
   * their own floor.
   */
  requestTimeoutMs?: number;
}

/**
 * Largest delay `setTimeout` schedules faithfully. Above it, and for `Infinity`
 * or `NaN`, timers fire almost immediately, which would reject every request.
 */
const MAX_REQUEST_TIMEOUT_MS = 2_147_483_647;

/**
 * Default bound for one request.
 *
 * 30s is this codebase's UI-grade budget: the package waits 20s for a
 * host-injected message port, and the playground bounds prompt-backed protocol
 * calls at 30s. A product that wants a tighter or looser bound sets
 * `requestTimeoutMs`.
 */
const DEFAULT_REQUEST_TIMEOUT_MS = 30_000;

/**
 * Floor for a request the host answers behind a remote authority, above the
 * runtime's 180s remote-authority response deadline
 * (`rust/crates/truapi-server/src/runtime.rs`,
 * `DEFAULT_REMOTE_AUTHORITY_RESPONSE_TIMEOUT`).
 */
const REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS = 190_000;

/**
 * Floor for a request whose answer waits on a person and carries no host-side
 * deadline at all: a pairing login, a device or remote consent dialog, a
 * payment confirmation. The host keeps such a call pending for as long as the
 * person takes, so this is the client's own ceiling rather than a cleared host
 * deadline, and it matches the longest client-side budget this repo already
 * uses for a prompt-backed call.
 */
const USER_APPROVAL_REQUEST_TIMEOUT_MS = 420_000;

/**
 * Floor for a request that waits on a live resource allocation or an on-chain
 * preimage, above the runtime's 300s allocation cap and 360s preimage cap.
 */
const LIVE_ALLOCATION_REQUEST_TIMEOUT_MS = 420_000;

/**
 * Requests whose answer either outlives `DEFAULT_REQUEST_TIMEOUT_MS` under a
 * host deadline or waits on a person with no host deadline at all, keyed by
 * request frame id. The effective bound is the larger of the configured bound
 * and the floor, so bounding a request never aborts an answer the host is
 * still allowed to send. A method absent from this table takes the configured
 * bound; a per-request `timeoutMs` overrides both.
 *
 * Every request frame id is classified here or as prompt-free in
 * `client.test.ts`, so a generated method added without a floor fails that
 * test rather than silently inheriting the default.
 */
export const REQUEST_TIMEOUT_FLOOR_MS: ReadonlyMap<number, number> = new Map([
  [W.ACCOUNT_GET_ACCOUNT.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [W.ACCOUNT_GET_ACCOUNT_ALIAS.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [W.ACCOUNT_CREATE_ACCOUNT_PROOF.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [W.ACCOUNT_SIGN_VRF.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [
    W.ACCOUNT_REGISTER_RING_VRF_KEY.request,
    REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS,
  ],
  [W.ACCOUNT_LIST_RING_VRF_KEYS.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [W.ACCOUNT_RING_VRF_SIGN.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [W.SIGNING_SIGN_PAYLOAD.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [W.SIGNING_SIGN_RAW.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [
    W.SIGNING_SIGN_PAYLOAD_WITH_LEGACY_ACCOUNT.request,
    REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS,
  ],
  [
    W.SIGNING_SIGN_RAW_WITH_LEGACY_ACCOUNT.request,
    REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS,
  ],
  [W.SIGNING_CREATE_TRANSACTION.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [
    W.SIGNING_CREATE_TRANSACTION_WITH_LEGACY_ACCOUNT.request,
    REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS,
  ],
  [W.STATEMENT_STORE_CREATE_PROOF.request, REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS],
  [
    W.STATEMENT_STORE_CREATE_PROOF_AUTHORIZED.request,
    REMOTE_AUTHORITY_REQUEST_TIMEOUT_MS,
  ],
  [W.ACCOUNT_REQUEST_LOGIN.request, USER_APPROVAL_REQUEST_TIMEOUT_MS],
  [
    W.PERMISSIONS_REQUEST_DEVICE_PERMISSION.request,
    USER_APPROVAL_REQUEST_TIMEOUT_MS,
  ],
  [
    W.PERMISSIONS_REQUEST_REMOTE_PERMISSION.request,
    USER_APPROVAL_REQUEST_TIMEOUT_MS,
  ],
  [W.PAYMENT_REQUEST.request, USER_APPROVAL_REQUEST_TIMEOUT_MS],
  [W.PAYMENT_TOP_UP.request, USER_APPROVAL_REQUEST_TIMEOUT_MS],
  [W.RESOURCE_ALLOCATION_REQUEST.request, LIVE_ALLOCATION_REQUEST_TIMEOUT_MS],
  [W.PREIMAGE_SUBMIT.request, LIVE_ALLOCATION_REQUEST_TIMEOUT_MS],
  [W.STATEMENT_STORE_SUBMIT.request, LIVE_ALLOCATION_REQUEST_TIMEOUT_MS],
]);

/**
 * Validate a caller-supplied request bound, rejecting the values `setTimeout`
 * would silently collapse into an immediate fire.
 */
function checkRequestTimeoutMs(value: number): number {
  if (
    !Number.isSafeInteger(value) ||
    value < 1 ||
    value > MAX_REQUEST_TIMEOUT_MS
  ) {
    throw new Error(
      `Invalid TrUAPI request timeout: ${value}. Expected an integer between 1 and ${MAX_REQUEST_TIMEOUT_MS}.`,
    );
  }
  return value;
}

/**
 * Resolve the bound one request is armed with: a per-request `timeoutMs` wins
 * outright, otherwise the larger of the transport's bound and the method's
 * floor, so a product that deliberately configures a long bound keeps it and
 * one that configures a short bound still cannot abort an answer the host is
 * allowed to send.
 */
export function resolveRequestTimeoutMs(
  requestFrameId: number,
  transportTimeoutMs: number,
  perRequestTimeoutMs: number | undefined,
): number {
  if (perRequestTimeoutMs !== undefined) {
    return checkRequestTimeoutMs(perRequestTimeoutMs);
  }
  return Math.max(
    transportTimeoutMs,
    REQUEST_TIMEOUT_FLOOR_MS.get(requestFrameId) ?? 0,
  );
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
 * Build a `TrUApiTransport` on top of a `WireProvider`, adding request/response
 * correlation and subscription start/receive/stop lifecycle handling.
 */
export function createTransport(
  provider: WireProvider,
  options: CreateTransportOptions = {},
): TrUApiTransport {
  const codecVersion = options.codecVersion ?? TRUAPI_CODEC_VERSION;
  const requestTimeoutMs =
    options.requestTimeoutMs === undefined
      ? DEFAULT_REQUEST_TIMEOUT_MS
      : checkRequestTimeoutMs(options.requestTimeoutMs);
  let idCounter = 0;
  let closedError: Error | null = null;
  const pending = new Map<
    string,
    {
      ids: RequestFrameIds;
      resolve: (value: Uint8Array) => void;
      reject: (error: Error) => void;
      timer: ReturnType<typeof setTimeout>;
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
  const hostRoutes = new Map<number, HostRoute>();

  /**
   * Normalize arbitrary thrown values into `Error` instances.
   */
  function toError(error: unknown): Error {
    return error instanceof Error ? error : new Error(String(error));
  }

  /**
   * Remove a pending request and cancel its timeout timer. Every settle path
   * goes through here, so a settled request never leaves a live timer and a
   * frame arriving after the bound fired finds no entry to resolve.
   */
  function takePending(requestId: string) {
    const entry = pending.get(requestId);
    if (!entry) return undefined;
    pending.delete(requestId);
    clearTimeout(entry.timer);
    return entry;
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
      takePending(requestId);
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

    if (payload.id === W.SYSTEM_HANDSHAKE.request) {
      // Auto-respond to inbound `host_handshake_request` frames.
      //
      // Legacy hosts shipping `@novasamatech/host-api@0.6.x` (e.g. dotli)
      // initiate their own handshake from the host side at startup and ping
      // the iframe with `host_handshake_request` every 50ms until they see a
      // matching response. The legacy host-api `createTransport` registered
      // an internal handler for this message; preserving that behaviour
      // keeps `@parity/truapi` a drop-in replacement for legacy bridges.
      //
      // Respond with the handshake method's selected wire version. The inner
      // request carries the wire codec version.
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
        closeWithError(toError(error));
        return;
      }
      try {
        send({
          requestId,
          payload: {
            id: W.SYSTEM_HANDSHAKE.response,
            value: response,
          },
        });
      } catch {
        // provider already closed
      }
      return;
    }

    const hostRoute = hostRoutes.get(payload.id);
    if (hostRoute) {
      startHostSubscription(hostRoute, requestId, payload.value);
      return;
    }
    for (const candidate of hostRoutes.values()) {
      if (payload.id !== candidate.ids.stop) continue;
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
      if (payload.id !== p.ids.response) {
        return;
      }
      takePending(requestId);
      try {
        p.resolve(payload.value);
      } catch (error) {
        p.reject(toError(error));
      }
      return;
    }

    const subscription = subscriptions.get(requestId);
    if (subscription) {
      if (payload.id === subscription.ids.receive) {
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
      } else if (payload.id === subscription.ids.interrupt) {
        subscriptions.delete(requestId);
        subscription.onInterrupt?.(payload.value);
      }
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
          id: route.ids.interrupt,
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
              payload: { id: route.ids.receive, value: route.encodeItem(item) },
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
      timeoutMs,
    }: RequestParams<Ok, Err>): ResultAsync<Ok, Err> {
      const bound = resolveRequestTimeoutMs(
        ids.request,
        requestTimeoutMs,
        timeoutMs,
      );
      const promise = new Promise<ResultPayload<Ok, Err>>((resolve, reject) => {
        if (closedError) {
          reject(closedError);
          return;
        }

        const requestId = `p:${++idCounter}`;
        const timer = setTimeout(() => {
          takePending(requestId);
          reject(new RequestTimeoutError(bound));
        }, bound);
        pending.set(requestId, {
          ids,
          resolve: (response) => resolve(decodeResponse(response)),
          reject,
          timer,
        });
        try {
          send({
            requestId,
            payload: {
              id: ids.request,
              value: payload,
            },
          });
        } catch (error) {
          takePending(requestId);
          reject(toError(error));
        }
      });
      return ResultAsync.fromSafePromise(promise).andThen(
        (result): ResultAsync<Ok, Err> =>
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
            id: ids.start,
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
                id: ids.stop,
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
      if (hostRoutes.has(ids.start)) {
        throw new Error(
          `host-initiated subscription ${ids.start} is already registered`,
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
      hostRoutes.set(ids.start, route);
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
