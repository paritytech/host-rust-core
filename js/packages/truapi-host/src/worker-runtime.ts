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
import {
  createWorkerRawCallbacks,
  type CallbackName,
  type OptionalCapabilities,
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
  handlePublishChatAction,
  handleRenderCustomMessageStart,
  stopRender,
  stopRendersForCore,
  type RenderSubscriptions,
} from "./worker-chat.js";
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
function buildRawCallbacks(capabilities: OptionalCapabilities) {
  return createWorkerRawCallbacks(
    {
      callbackRequest,
      startSubscription,
      chainConnect,
    },
    capabilities,
  );
}

function buildCoreCallbacks(coreId: number) {
  return {
    emitFrame(frame: Uint8Array): void {
      postToMain({ kind: "frame", coreId, bytes: frame });
    },
    dispose(): void {
      // Main thread owns lifecycle and disposes explicitly.
    },
  };
}

let runtime: WorkerPairingHostRuntime | null = null;
const cores = new Map<number, WorkerProductRuntime>();
/** Live custom-message render subscriptions, keyed by main-thread render id. */
const renders: RenderSubscriptions = new Map();
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
      try {
        runtime = new wasm.WasmPairingHostRuntime(
          buildRawCallbacks(msg.capabilities),
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
    case "getProductSubtreePublicKey":
      void handleGetProductSubtreePublicKey(msg.requestId, msg.productId);
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
    case "publishChatAction":
      handlePublishChatAction(
        cores.get(msg.coreId),
        postToMain,
        msg.coreId,
        msg.requestId,
        msg.action,
      );
      break;
    case "renderCustomMessageStart":
      handleRenderCustomMessageStart(
        cores.get(msg.coreId),
        postToMain,
        renders,
        msg.coreId,
        msg.renderId,
        msg.messageId,
        msg.messageType,
        msg.payload,
      );
      break;
    case "renderCustomMessageStop":
      stopRender(renders, msg.renderId);
      break;
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
  // A render subscription outliving its core would call into freed wasm.
  stopRendersForCore(renders, coreId);
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

async function handleGetProductSubtreePublicKey(
  requestId: number,
  productId: string,
): Promise<void> {
  if (!runtime) {
    postToMain({
      kind: "productSubtreePublicKeyResponse",
      requestId,
      ok: false,
      error: "getProductSubtreePublicKey received before runtime is ready",
    });
    return;
  }
  try {
    postToMain({
      kind: "productSubtreePublicKeyResponse",
      requestId,
      ok: true,
      key: await runtime.productSubtreePublicKey(productId),
    });
  } catch (err) {
    postToMain({
      kind: "productSubtreePublicKeyResponse",
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
