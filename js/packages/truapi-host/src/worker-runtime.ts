/// <reference lib="webworker" />
// Worker entrypoint. Loads the web-targeted truapi-server WASM bundle and
// bridges every host callback over postMessage. The main thread keeps the
// state that needs DOM access (localStorage, prompts) while the core dispatcher
// runs here off the page main thread.

import type {
  MainToWorker,
  SubscriptionName,
  WorkerToMain,
} from "./worker-protocol.js";
import type { GenericError } from "@parity/truapi";
import { TRUAPI_CODEC_VERSION } from "@parity/truapi";
import {
  createWorkerRawCallbacks,
  type CallbackName,
} from "./generated/worker-callbacks.js";
import {
  handleGetPermissionAuthorizationStatus,
  handleGetPermissionAuthorizationStatuses,
  handleSetPermissionAuthorizationStatus,
} from "./worker-permission-authorization.js";
import type {
  WasmModuleShape,
  WorkerPairingHostRuntime,
  WorkerProductRuntime,
} from "./wasm-module.js";
import { errorMessage } from "./error.js";
import {
  dispatchChainResponse,
  dispatchSubscriptionError,
  dispatchSubscriptionItem,
  type SubscriptionListeners,
} from "./worker-dispatch.js";

// A literal specifier so bundlers resolve the glue statically and emit it
// alongside `truapi_server_bg.wasm`. It is typed by the ambient declaration in
// `src/wasm/web/`, and resolves against `dist/worker-runtime.js` at runtime,
// where `make wasm` puts the artifact.
const wasmModulePromise: Promise<WasmModuleShape> =
  import("./wasm/web/truapi_server.js");

const ctx = self as unknown as DedicatedWorkerGlobalScope;

function postToMain(msg: WorkerToMain): void {
  ctx.postMessage(msg);
}

let nextRequestId = 0;
const pendingCallbacks = new Map<
  number,
  (result: { ok: true; value: unknown } | { ok: false; error: string }) => void
>();

let nextSubId = 0;
const subscriptionListeners = new Map<number, SubscriptionListeners>();

let nextConnId = 0;
type ChainConnectAck = { ok: true } | { ok: false; error: string };
const chainConnectAcks = new Map<number, (ack: ChainConnectAck) => void>();
const chainResponseListeners = new Map<number, (json: string) => void>();

function callbackRequest(
  name: CallbackName,
  args: readonly unknown[],
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const requestId = ++nextRequestId;
    pendingCallbacks.set(requestId, (r) => {
      if (r.ok) resolve(r.value);
      else reject(new Error(r.error));
    });
    postToMain({ kind: "callbackRequest", requestId, name, args });
  });
}

function startSubscription<T>(
  name: SubscriptionName,
  payload: Uint8Array | null,
  sendItem: (value: T) => void,
  sendError: (error: GenericError) => void,
): () => void {
  const subId = ++nextSubId;
  subscriptionListeners.set(subId, {
    sendItem: sendItem as (value: unknown) => void,
    sendError: (error) => sendError({ reason: error }),
  });
  postToMain({ kind: "subscriptionStart", subId, name, payload });
  return () => {
    subscriptionListeners.delete(subId);
    postToMain({ kind: "subscriptionStop", subId });
  };
}

interface WorkerChainConnection {
  send(request: string): void;
  close(): void;
}

/**
 * Worker-side half of the host chain-connect bridge.
 *
 * The Rust core runs in this worker but owns no socket. When it needs chain
 * access (chainHead v1 for People-chain identity / statement-store SSO) it
 * calls this; the actual transport lives on the host main thread and is reached
 * over postMessage. The data crossing here is JSON-RPC strings, not SCALE: only
 * the product<->core wire is SCALE.
 *
 *   per-tab / sandboxed          core-owned (this Web Worker)       host-owned (main thread)
 *   +-------------------+  SCALE  +--------------------------+      +--------------------------------+
 *   | Product (iframe)  |<------->| truapi-server WASM core  |      | host.connect() (ChainProvider) |
 *   | speaks TrUAPI     |  frames | chainHead v1, SSO,       |      | host-owned JSON-RPC transport  |
 *   | never sees chains |         | People-chain identity    |      | remote RPC, native client, ... |
 *   +-------------------+         +--------------------------+      +--------------------------------+
 *                                      |   ^  JSON-RPC strings (not SCALE)        ^   |
 *                       chainConnect() |   | onResponse(json)           connect   |   | responses()
 *                         (this fn)    v   |                                      |   v
 *                 worker-runtime.ts  <======== postMessage ========>  create-worker-host-runtime.ts
 *                 chainConnectStart / chainSend / chainClose   -->   handleChainConnect* -> host.connect()
 *                 chainConnectAck   / chainResponse            <--   (pumped from connection.responses())
 *
 * Allocates a `connId`, posts `chainConnectStart`, and resolves a
 * `{ send, close }` handle once the main thread acks. `send` posts `chainSend`,
 * `close` posts `chainClose`, and every `chainResponse` for this `connId` is
 * delivered to `onResponse`.
 */
function chainConnect(
  genesisHash: string,
  onResponse: (json: string) => void,
): Promise<WorkerChainConnection | null> {
  const connId = ++nextConnId;
  return new Promise((resolve, reject) => {
    chainConnectAcks.set(connId, (ack) => {
      if (!ack.ok) {
        chainResponseListeners.delete(connId);
        reject(new Error(ack.error));
        return;
      }
      resolve({
        send(request: string) {
          postToMain({ kind: "chainSend", connId, request });
        },
        close() {
          chainResponseListeners.delete(connId);
          postToMain({ kind: "chainClose", connId });
        },
      });
    });
    chainResponseListeners.set(connId, onResponse);
    postToMain({ kind: "chainConnectStart", connId, genesisHash });
  });
}

/** Build the host-level callback object passed to the WASM runtime. */
function buildRawCallbacks() {
  return createWorkerRawCallbacks({
    callbackRequest,
    startSubscription,
    chainConnect,
  });
}

/** Encode raw frame bytes as base64 (JSON can't carry binary over the WS). */
function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

/**
 * Envelope version stamped on each frame, mirroring the debugger's
 * `WIRE_ENVELOPE_VERSION`. Kept in sync by hand (a value constant, not a shared
 * dep, to avoid truapi-host depending on the debugger package).
 */
const WIRE_ENVELOPE_VERSION = 1;

/**
 * Is `url` a `ws://` URL on a loopback host? The debug tap forwards raw frames
 * (including sensitive payloads, before the debugger's denylist runs), so it is
 * loopback-only: refuse to stream them off the local machine. `ws://` only,
 * matching the native sink (`native_debug.rs`), which is also ws-only.
 *
 * Cleartext is the right call *because* the target is loopback-only. TLS defends
 * against a party on the path, and a loopback socket has no path: the frames
 * never reach an interface. `wss://` would instead require the debugger to
 * present a certificate — unobtainable for `localhost` from a real CA, and
 * self-signed on iOS costs the developer a CA install plus a manual enable under
 * Settings → General → About → Certificate Trust Settings before a single frame
 * arrives. So `wss://` buys no confidentiality here and costs setup, while adding
 * a second protocol path and a trust surface to the gate.
 *
 * Confidentiality for the trace stream comes from the loopback check, not from
 * the scheme: the frames never cross a network, so there is nothing on a network
 * to encrypt. A *remote* debugger would need TLS **and** authentication **and**
 * an explicit opt-in; none of that is a scheme this gate silently accepts today.
 *
 * Unlike `WsDebugSink::connect`, which resolves the host and requires every
 * resolved address to be loopback, this matches the hostname the URL parser
 * normalized. There is no resolver in a Web Worker, and none is needed: the same
 * `url` string is passed to `new WebSocket(url)` below, so the browser resolves
 * exactly what was validated. The Rust "validate one string, dial another" gap
 * cannot open here because there is only ever one string.
 */
export function isLoopbackWsUrl(url: string): boolean {
  try {
    const u = new URL(url);
    if (u.protocol !== "ws:") return false;
    const host = u.hostname.replace(/^\[|\]$/g, "").toLowerCase();
    return (
      host === "localhost" ||
      host === "::1" ||
      /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host) ||
      // IPv4-mapped loopback: WHATWG serializes ::ffff:127.x.y.z as ::ffff:7fxx:yyyy.
      /^::ffff:7f[0-9a-f]{2}:/.test(host)
    );
  } catch {
    return false;
  }
}

/**
 * The wire-contract fingerprint of the core that *encodes* the frames, or
 * `undefined` when this build of the core does not report one.
 *
 * The debugger decodes each frame against a `frameId → method` table, so the
 * `schema` an envelope carries has to be the fingerprint of the table the bytes
 * were encoded with. That is the WASM core's, not `@parity/truapi`'s: the client
 * and the core are separate artifacts, and `dist/wasm/web/` is gitignored and
 * built by hand (`make wasm`), so a stale core beside a fresh client is the
 * everyday case rather than an exotic one. Stamping the client's hash there would
 * make the debugger *confirm* identity on frames from a different table and decode
 * them into the wrong methods and values, silently.
 *
 * When the core does not report a hash, the envelope carries none. The debugger
 * treats an unstamped frame as unconfirmed: it still groups the op, but refuses
 * to decode values. Losing decode until `make wasm` is rerun is the honest
 * outcome; a confident wrong decode is not.
 */
export function coreWireSchemaHash(module: {
  wireSchemaHash?: () => string;
}): string | undefined {
  let hash: unknown;
  try {
    hash = module.wireSchemaHash?.();
  } catch {
    hash = undefined;
  }
  if (typeof hash === "string" && hash.length > 0) return hash;
  console.warn(
    "[truapi] wire debugger: this WASM core does not report its wire-schema hash — frames will stream without a `schema` stamp and the debugger will group them but refuse to decode values (rebuild the core with `make wasm`)",
  );
  return undefined;
}

/**
 * The socket surface the debugger link uses. A `WebSocket` satisfies it; tests
 * substitute a fake to drive backpressure and reconnect timing without a network.
 */
export interface DebuggerSocket {
  /** Bytes handed to the socket that it has not yet put on the wire. */
  readonly bufferedAmount: number;
  send(data: string): void;
  close(): void;
  addEventListener(type: "open" | "close" | "error", listener: () => void): void;
}

/** Construction options for {@link createDebuggerLink}. */
export interface DebuggerLinkOptions {
  /**
   * The encoding core's wire-schema hash, from {@link coreWireSchemaHash}. When
   * omitted, envelopes carry no `schema` and the debugger refuses value decode
   * rather than trusting a hash the core never vouched for.
   */
  schema?: string;
  /** Socket factory. Defaults to a real `WebSocket`; tests inject a fake. */
  createSocket?: (url: string) => DebuggerSocket;
  /** Deferred scheduler for reconnect backoff. Defaults to `setTimeout`. */
  schedule?: (run: () => void, delayMs: number) => void;
}

/** Initial reconnect delay; doubles per failed dial up to {@link RECONNECT_MAX_MS}. */
const RECONNECT_BASE_MS = 200;

/** Cap on the reconnect backoff. Mirrors the native sink's `MAX_BACKOFF`. */
const RECONNECT_MAX_MS = 5000;

/**
 * Ceiling on the socket's *own* unflushed send buffer before frames are shed.
 *
 * The queue caps below only bound what this module holds while the socket is
 * down. A socket that is open but whose peer has stopped reading keeps
 * `readyState === OPEN` while `bufferedAmount` grows without limit, and that
 * growth is charged to the observed session's worker: handing frames to it
 * unchecked is the same unbounded buffering the queue caps exist to prevent, one
 * layer lower. Over this ceiling, frames are shed into the counted `dropped`
 * instead.
 */
const MAX_SOCKET_BUFFERED_BYTES = 8 * 1024 * 1024;

/**
 * Dev-only link to the debugger the host dials. Fire-and-forget by construction:
 * it opens lazily, buffers a bounded backlog until the socket is up, retries a
 * dropped connection with capped backoff, sheds frames (counted) rather than
 * buffering without bound at either layer, and swallows every error - a slow,
 * absent, or crashed debugger only loses the trace, it can never throw into the
 * frame path.
 */
export function createDebuggerLink(
  url: string,
  options: DebuggerLinkOptions = {},
): {
  emit(channelId: string, dir: string, frame: Uint8Array): void;
} {
  // Loopback-only, dev-only: a non-loopback (or non-ws://) debugger URL yields an
  // inert link rather than streaming frames across the network. Warn so a
  // mistyped value reads as "misconfigured", not "the debugger doesn't work".
  if (!isLoopbackWsUrl(url)) {
    console.warn(
      `[truapi] wire debugger URL rejected (must be ws:// on a loopback host): ${url}`,
    );
    return { emit() {} };
  }
  const createSocket =
    options.createSocket ?? ((target: string) => new WebSocket(target));
  const schedule =
    options.schedule ??
    ((run: () => void, delayMs: number) => {
      setTimeout(run, delayMs);
    });
  const schema = options.schema;
  let socket: DebuggerSocket | null = null;
  let open = false;
  const queue: string[] = [];
  // Count *and* byte caps: each queued item is a base64 ProtocolMessage (storage
  // writes, RPC responses - up to MBs each), so a count-only cap would let a slow
  // or absent debugger buffer unbounded RSS on the observed session. Whichever
  // ceiling hits first drops the frame (counted), never blocking the frame path.
  const MAX_QUEUE = 1000;
  const MAX_QUEUE_BYTES = 8 * 1024 * 1024;
  let queuedBytes = 0;
  let droppedSinceSend = 0;
  let reconnectDelayMs = RECONNECT_BASE_MS;
  let reconnectScheduled = false;

  /**
   * Dial again after the current backoff, at most one dial in flight.
   *
   * Without the delay this ran once per frame: a busy session with no debugger
   * listening dialed loopback hundreds of times a second (each refused
   * immediately, each logging a console error), because every emit found
   * `socket === null` and redialled. The native sink has always backed off; this
   * mirrors it.
   */
  function scheduleReconnect(): void {
    if (socket !== null || reconnectScheduled) return;
    reconnectScheduled = true;
    const delayMs = reconnectDelayMs;
    reconnectDelayMs = Math.min(reconnectDelayMs * 2, RECONNECT_MAX_MS);
    try {
      schedule(() => {
        reconnectScheduled = false;
        if (socket === null) connect();
      }, delayMs);
    } catch {
      // No timer available: fall back to redialling on the next emit.
      reconnectScheduled = false;
    }
  }

  /** Drain the backlog onto a freshly opened socket. */
  function flush(): void {
    const pending = queue.splice(0);
    queuedBytes = 0;
    // Deliver drops accumulated while disconnected by stamping the count on the
    // first drained frame - a bare marker without channelId/dir/frame wouldn't
    // parse server-side. Drops only happen once the queue is full, so when the
    // count is nonzero there is always a pending frame to carry it; if not, it
    // rides the next live emit.
    if (pending.length > 0 && droppedSinceSend > 0) {
      try {
        const first = JSON.parse(pending[0]) as Record<string, unknown>;
        first.dropped = droppedSinceSend;
        pending[0] = JSON.stringify(first);
        droppedSinceSend = 0;
      } catch {
        // Leave the frame as-is; the count rides the next live emit.
      }
    }
    for (const message of pending) send(message);
  }

  function connect(): void {
    let dialed: DebuggerSocket;
    try {
      dialed = createSocket(url);
    } catch {
      socket = null;
      scheduleReconnect();
      return;
    }
    socket = dialed;
    dialed.addEventListener("open", () => {
      open = true;
      // A dial that reached the debugger earns the short delay back, so a
      // debugger that restarts is picked up promptly rather than after the cap.
      reconnectDelayMs = RECONNECT_BASE_MS;
      flush();
    });
    dialed.addEventListener("close", () => {
      open = false;
      if (socket === dialed) socket = null;
    });
    dialed.addEventListener("error", () => {
      // A socket that fired `error` is dead: close it explicitly (tidiness), then
      // null it so the next emit schedules a redial. Without the null, a runtime
      // that fires `error` without a following `close` would leave `socket`
      // non-null and frames would buffer then drop.
      open = false;
      if (socket === dialed) socket = null;
      try {
        dialed.close();
      } catch {
        // already closed / closing
      }
    });
  }

  function send(message: string): void {
    try {
      socket?.send(message);
    } catch {
      // A dead socket must never break the frame path.
    }
  }

  connect();

  let warnedDrop = false;
  /** Shed one frame into the counted backlog gap. */
  function shed(): void {
    droppedSinceSend += 1;
    if (!warnedDrop) {
      // The link buffers a bounded backlog while the debugger is absent/slow, and
      // stops handing frames to a socket that is not draining. Warn once so the
      // gap is attributable to the link, not the host.
      warnedDrop = true;
      console.warn(
        "[truapi] wire debugger link is not keeping up — dropping frames (counted in `dropped`) until it drains",
      );
    }
  }

  return {
    emit(channelId, dir, frame) {
      // A debug tap must never throw into the observed frame path: toBase64 /
      // JSON.stringify can raise on a pathological frame (btoa or V8 string-length
      // limits), and only send() swallows its own errors. Losing a trace is fine;
      // breaking dispatch is not.
      try {
        const live = open ? socket : null;
        // Checked before encoding, so a shed frame costs no base64 either.
        if (live !== null && live.bufferedAmount > MAX_SOCKET_BUFFERED_BYTES) {
          shed();
          return;
        }
        const base = {
          v: WIRE_ENVELOPE_VERSION,
          codec: TRUAPI_CODEC_VERSION,
          // Only when the core vouched for it: see coreWireSchemaHash.
          ...(schema !== undefined ? { schema } : {}),
          channelId,
          dir,
          // The producer is the only party that knows when the frame crossed. The
          // debugger's own clock is the flush instant for anything that waited in
          // the queue below, which collapses every duration in a backlog to 0ms
          // and pulls ops minutes apart into one retry-storm window.
          observedAt: Date.now(),
          frame: toBase64(frame),
        };
        if (live !== null) {
          // Piggyback any frames dropped while the link was down onto the next
          // live frame, so the debugger attributes the gap to the link, not the
          // host.
          send(
            droppedSinceSend > 0
              ? JSON.stringify({ ...base, dropped: droppedSinceSend })
              : JSON.stringify(base),
          );
          droppedSinceSend = 0;
          return;
        }
        // Nothing leaves the queue except through flush(), so everything that
        // enters it is by definition replayed rather than live: mark it here and
        // the debugger can tell a backlog gap from a quiet session. Its
        // `observedAt` above is already the real crossing time, so the marker is
        // provenance, not a correction.
        const message = JSON.stringify({ ...base, buffered: true });
        if (
          queue.length < MAX_QUEUE &&
          queuedBytes + message.length <= MAX_QUEUE_BYTES
        ) {
          queue.push(message);
          queuedBytes += message.length;
        } else {
          shed();
        }
        scheduleReconnect();
      } catch {
        // Swallow: never let the tap disturb the frame path.
      }
    },
  };
}

let debuggerLink: ReturnType<typeof createDebuggerLink> | null = null;

function buildCoreCallbacks(coreId: number) {
  const callbacks = {
    emitFrame(frame: Uint8Array): void {
      postToMain({ kind: "frame", coreId, bytes: frame });
    },
    dispose(): void {
      // Main thread owns lifecycle and disposes explicitly.
    },
  };
  if (!debuggerLink) return callbacks;
  // Adding `debugEmit` is what makes the Rust host install its debug sink; when
  // no debugger is configured it is absent and the tap stays inert.
  return {
    ...callbacks,
    debugEmit(channelId: string, dir: string, frame: Uint8Array): void {
      debuggerLink?.emit(channelId, dir, frame);
    },
  };
}

let runtime: WorkerPairingHostRuntime | null = null;
const cores = new Map<number, WorkerProductRuntime>();
let wasm: WasmModuleShape | null = null;

(async () => {
  try {
    wasm = await wasmModulePromise;
    await wasm.default();
    postToMain({ kind: "loaded" });
  } catch (err) {
    postToMain({ kind: "fatalError", error: errorMessage(err) });
  }
})();

ctx.addEventListener("message", (ev: MessageEvent<MainToWorker>) => {
  const msg = ev.data;
  switch (msg.kind) {
    case "init":
      if (!wasm) {
        postToMain({
          kind: "fatalError",
          error: "init received before WASM loaded",
        });
        break;
      }
      if (runtime) {
        postToMain({
          kind: "fatalError",
          error: "init: runtime already initialized",
        });
        break;
      }
      wasm.setLogLevel?.(msg.logLevel);
      if (msg.debuggerUrl && !debuggerLink) {
        // The hash comes from the core that will encode the frames, not from this
        // package's client constant: they are separate artifacts and the WASM
        // bundle is built by hand.
        debuggerLink = createDebuggerLink(msg.debuggerUrl, {
          schema: coreWireSchemaHash(wasm),
        });
      }
      try {
        runtime = new wasm.WasmPairingHostRuntime(
          buildRawCallbacks(),
          msg.hostConfig,
        );
        postToMain({ kind: "ready" });
      } catch (err) {
        postToMain({ kind: "fatalError", error: `init: ${errorMessage(err)}` });
      }
      break;
    case "createCore":
      if (!runtime) {
        postToMain({
          kind: "coreError",
          coreId: msg.coreId,
          error: "createCore received before runtime is ready",
        });
        break;
      }
      try {
        const core = runtime.productRuntime(
          msg.product,
          buildCoreCallbacks(msg.coreId),
        );
        cores.set(msg.coreId, core);
        postToMain({ kind: "coreReady", coreId: msg.coreId });
      } catch (err) {
        postToMain({
          kind: "coreError",
          coreId: msg.coreId,
          error: errorMessage(err),
        });
      }
      break;
    case "setLogLevel":
      wasm?.setLogLevel?.(msg.level);
      break;
    case "frame":
      void handleFrame(msg.coreId, msg.bytes);
      break;
    case "disconnectSession":
      void handleDisconnectSession(msg.requestId);
      break;
    case "cancelPairing":
      runtime?.cancelPairing();
      break;
    case "getSessionChatIdentityKey":
      handleGetSessionChatIdentityKey(msg.requestId);
      break;
    case "getDeviceEncryptionKey":
      void handleGetDeviceEncryptionKey(msg.requestId);
      break;
    case "notifySessionStoreChanged":
      runtime?.notifySessionStoreChanged();
      break;
    case "activateStoredSession":
      void handleSessionActivation(
        msg.requestId,
        "activateStoredSession",
        (rt) => rt.activateStoredSession(),
      );
      break;
    case "activateExternalSession": {
      const { blob } = msg;
      void handleSessionActivation(
        msg.requestId,
        "activateExternalSession",
        (rt) => rt.activateExternalSession(blob),
      );
      break;
    }
    case "resetSessionState":
      void handleSessionActivation(msg.requestId, "resetSessionState", (rt) =>
        rt.resetSessionState(),
      );
      break;
    case "getPermissionAuthorizationStatus":
      void handleGetPermissionAuthorizationStatus(
        runtime,
        postToMain,
        msg.productId,
        msg.requestId,
        msg.request,
      );
      break;
    case "getPermissionAuthorizationStatuses":
      void handleGetPermissionAuthorizationStatuses(
        runtime,
        postToMain,
        msg.productId,
        msg.requestId,
        msg.requests,
      );
      break;
    case "setPermissionAuthorizationStatus":
      void handleSetPermissionAuthorizationStatus(
        runtime,
        postToMain,
        msg.productId,
        msg.requestId,
        msg.request,
        msg.status,
      );
      break;
    case "callbackResponse": {
      const cb = pendingCallbacks.get(msg.requestId);
      if (cb) {
        pendingCallbacks.delete(msg.requestId);
        cb(
          msg.ok
            ? { ok: true, value: msg.value }
            : { ok: false, error: msg.error },
        );
      }
      break;
    }
    case "subscriptionItem": {
      dispatchSubscriptionItem(
        msg.subId,
        msg.value,
        subscriptionListeners,
        postToMain,
      );
      break;
    }
    case "subscriptionError": {
      dispatchSubscriptionError(
        msg.subId,
        msg.error,
        subscriptionListeners,
        postToMain,
      );
      break;
    }
    case "chainConnectAck": {
      const cb = chainConnectAcks.get(msg.connId);
      if (cb) {
        chainConnectAcks.delete(msg.connId);
        cb(msg.ok ? { ok: true } : { ok: false, error: msg.error });
      }
      break;
    }
    case "chainResponse": {
      dispatchChainResponse(
        msg.connId,
        msg.json,
        chainResponseListeners,
        postToMain,
      );
      break;
    }
    case "disposeCore":
      disposeCore(msg.coreId);
      break;
    case "dispose":
      try {
        for (const coreId of [...cores.keys()]) {
          disposeCore(coreId);
        }
        runtime?.free();
      } catch (err) {
        postToMain({ kind: "disposeError", error: errorMessage(err) });
      }
      runtime = null;
      break;
    default: {
      const { kind } = msg as { kind?: unknown };
      console.warn(
        `[truapi worker-runtime] unknown message kind: ${String(kind)}`,
      );
    }
  }
});

function disposeCore(coreId: number): void {
  const core = cores.get(coreId);
  if (!core) return;
  cores.delete(coreId);
  try {
    core.dispose();
    core.free();
  } catch (err) {
    postToMain({ kind: "disposeError", error: errorMessage(err) });
  }
}

async function handleSessionActivation(
  requestId: number,
  label: string,
  activate: (runtime: WorkerPairingHostRuntime) => Promise<void>,
): Promise<void> {
  if (!runtime) {
    postToMain({
      kind: "sessionActivationResponse",
      requestId,
      ok: false,
      error: `${label} received before runtime is ready`,
    });
    return;
  }
  try {
    await activate(runtime);
    postToMain({ kind: "sessionActivationResponse", requestId, ok: true });
  } catch (err) {
    postToMain({
      kind: "sessionActivationResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}

async function handleDisconnectSession(requestId: number): Promise<void> {
  if (!runtime) {
    postToMain({
      kind: "disconnectSessionResponse",
      requestId,
      ok: false,
      error: "disconnectSession received before runtime is ready",
    });
    return;
  }
  try {
    await runtime.disconnectSession();
    postToMain({ kind: "disconnectSessionResponse", requestId, ok: true });
  } catch (err) {
    postToMain({
      kind: "disconnectSessionResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}

function handleGetSessionChatIdentityKey(requestId: number): void {
  if (!runtime) {
    postToMain({
      kind: "sessionChatIdentityKeyResponse",
      requestId,
      ok: false,
      error: "getSessionChatIdentityKey received before runtime is ready",
    });
    return;
  }
  try {
    postToMain({
      kind: "sessionChatIdentityKeyResponse",
      requestId,
      ok: true,
      key: runtime.sessionChatIdentityKey(),
    });
  } catch (err) {
    postToMain({
      kind: "sessionChatIdentityKeyResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}

async function handleGetDeviceEncryptionKey(requestId: number): Promise<void> {
  if (!runtime) {
    postToMain({
      kind: "deviceEncryptionKeyResponse",
      requestId,
      ok: false,
      error: "getDeviceEncryptionKey received before runtime is ready",
    });
    return;
  }
  try {
    postToMain({
      kind: "deviceEncryptionKeyResponse",
      requestId,
      ok: true,
      key: await runtime.deviceEncryptionKey(),
    });
  } catch (err) {
    postToMain({
      kind: "deviceEncryptionKeyResponse",
      requestId,
      ok: false,
      error: errorMessage(err),
    });
  }
}

async function handleFrame(coreId: number, bytes: Uint8Array): Promise<void> {
  const core = cores.get(coreId);
  if (!core) {
    postToMain({
      kind: "frameError",
      coreId,
      error: `frame received for unknown core ${coreId}`,
    });
    return;
  }
  try {
    await core.receiveFrame(bytes);
  } catch (err) {
    postToMain({
      kind: "frameError",
      coreId,
      error: errorMessage(err),
    });
  }
}
