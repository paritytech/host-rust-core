import type {
  ChainConnection,
  ProductRuntimeConfig,
  LogLevel,
  PermissionAuthorizationRequest,
  PermissionAuthorizationStatus,
  ProductExecutionKind,
  RequiredHostCallbacks,
  TrUApiProductProvider,
  WorkerDemandChange,
} from "../index.js";
import type {
  Bytes32,
  GenericError,
  HostChatActionSubscribeItem,
  HostRendererActionSubscribeItem,
  RendererNode,
} from "@parity/truapi";
import {
  HostChatActionSubscribeItem as HostChatActionSubscribeItemCodec,
  HostRendererActionSubscribeItem as HostRendererActionSubscribeItemCodec,
  ProductRendererRenderRequest as ProductRendererRenderRequestCodec,
  RendererNode as RendererNodeCodec,
} from "@parity/truapi";
import { PermissionAuthorizationRequest as PermissionAuthorizationRequestCodec } from "../generated/host-callbacks.js";
import { createWasmRawCallbacks } from "../generated/host-callbacks-adapter.js";
import type { RawCallbacks } from "../generated/host-callbacks-adapter.js";
import type {
  CallbackName,
  MainToWorker,
  SubscriptionName,
  WorkerToMain,
} from "../worker-protocol.js";
import { bytesToHex } from "@parity/truapi/scale";
import { startRawSubscription } from "../generated/worker-callbacks.js";
import { errorMessage, toError } from "../error.js";

export type WebWorkerHostConfig = Omit<
  ProductRuntimeConfig,
  "productId" | "executionKind"
>;

export interface WorkerPairingHostRuntime {
  /**
   * The encoding core's wire-schema hash, when the core reports one.
   *
   * An in-host debugger tap runs on this side of the worker boundary and has no
   * other way to reach it, so without this it can only stamp frames with the
   * page bundle's own constant — a different artifact from the core that
   * actually encoded them. The debugger then refuses to decode, exactly as it
   * should. Undefined for a core built before the export existed.
   */
  readonly coreWireSchemaHash: string | undefined;
  createProvider(product: {
    productId: string;
    executionKind?: ProductExecutionKind;
  }): Promise<TrUApiProductProvider>;
  disconnectSession(): Promise<void>;
  cancelPairing(): void;
  notifySessionStoreChanged(): void;
  /**
   * Restore the session persisted in the core's `AuthSession` slot. Resolves
   * once product frames may use it, so a host can await this at boot before
   * routing. Rejects when the runtime has been disposed or the worker faulted,
   * so a host never routes on an activation that did not run.
   */
  activateStoredSession(): Promise<void>;
  /**
   * Install an already-paired session the host holds itself, without copying
   * it into core storage. Rejects on a disposed runtime, as
   * {@link WorkerPairingHostRuntime.activateStoredSession} does.
   */
  activateExternalSession(blob: Uint8Array): Promise<void>;
  /**
   * Drop the active paired session without notifying the peer. Rejects on a
   * disposed runtime, as
   * {@link WorkerPairingHostRuntime.activateStoredSession} does.
   */
  resetSessionState(): Promise<void>;
  getPermissionAuthorizationStatus(
    productId: string,
    request: PermissionAuthorizationRequest,
  ): Promise<PermissionAuthorizationStatus>;
  getPermissionAuthorizationStatuses(
    productId: string,
    requests: PermissionAuthorizationRequest[],
  ): Promise<PermissionAuthorizationStatus[]>;
  setPermissionAuthorizationStatus(
    productId: string,
    request: PermissionAuthorizationRequest,
    status: PermissionAuthorizationStatus,
  ): Promise<void>;
  getSessionChatIdentityKey(): Promise<Uint8Array | undefined>;
  getDeviceEncryptionKey(): Promise<Uint8Array>;
  getProductSubtreePublicKey(
    productId: string,
    timeoutMs?: number,
  ): Promise<Uint8Array | undefined>;
  /**
   * Take one reference on a product's worker for a modality holder that is on
   * screen or in flight. Pair every call with one
   * {@link WorkerPairingHostRuntime.releaseWorker}. The core counts; the
   * resulting level reaches
   * {@link WorkerPairingHostRuntime.subscribeWorkerDemand} listeners, and the
   * host runs and stops the worker executable itself.
   */
  acquireWorker(productId: string): void;
  /** Release one reference. Releasing with none held is a no-op. */
  releaseWorker(productId: string): void;
  /**
   * Observe which product workers the host should run. The listener first
   * receives `wanted: true` for every product wanted right now, then each
   * change as it happens, and `wanted: false` for every remaining product
   * when the runtime is disposed. Returns the unsubscribe.
   */
  subscribeWorkerDemand(
    listener: (change: WorkerDemandChange) => void,
  ): () => void;
  setLogLevel(level: LogLevel): void;
  dispose(): void;
}

interface CoreState {
  coreId: number;
  productId: string;
  listeners: Set<(message: Uint8Array) => void>;
  closeListeners: Set<(error: Error) => void>;
  closedError: Error | null;
  disposed: boolean;
}

/**
 * One live render on the main thread. The core id rides along so disposing one
 * provider fails only its own renders.
 */
interface RenderEntry {
  coreId: number;
  onUpdate: (node: RendererNode) => void;
  onComplete: () => void;
  onError: (error: Error) => void;
}

interface RuntimeState {
  worker: Worker;
  rawCallbacks: RawCallbacks;
  cores: Map<number, CoreState>;
  pendingCores: Map<
    number,
    {
      productId: string;
      resolve: (provider: TrUApiProductProvider) => void;
      reject: (error: Error) => void;
    }
  >;
  subscriptionDisposers: Map<number, () => void>;
  chainConnections: Map<number, ChainConnection>;
  pendingDisconnects: Map<
    number,
    { resolve: () => void; reject: (error: Error) => void }
  >;
  pendingSessionActivations: Map<
    number,
    { resolve: () => void; reject: (error: Error) => void }
  >;
  pendingPermissionAuthorizationStatuses: Map<
    number,
    {
      resolve: (status: PermissionAuthorizationStatus) => void;
      reject: (error: Error) => void;
    }
  >;
  pendingPermissionAuthorizationStatusBatches: Map<
    number,
    {
      resolve: (statuses: PermissionAuthorizationStatus[]) => void;
      reject: (error: Error) => void;
    }
  >;
  pendingSetPermissionAuthorizationStatuses: Map<
    number,
    { resolve: () => void; reject: (error: Error) => void }
  >;
  pendingSessionChatIdentityKeys: Map<
    number,
    {
      resolve: (key: Uint8Array | undefined) => void;
      reject: (error: Error) => void;
    }
  >;
  pendingDeviceEncryptionKeys: Map<
    number,
    { resolve: (key: Uint8Array) => void; reject: (error: Error) => void }
  >;
  pendingProductSubtreePublicKeys: Map<
    number,
    {
      resolve: (key: Uint8Array | undefined) => void;
      reject: (error: Error) => void;
    }
  >;
  /** Host-authored Chat and Renderer actions awaiting the worker's response. */
  pendingActions: Map<
    number,
    { resolve: () => void; reject: (error: Error) => void }
  >;
  /** Sinks for live renders, keyed by render id. */
  renders: Map<number, RenderEntry>;
  /** Products whose worker the core currently wants, for late subscribers. */
  wantedWorkers: Set<string>;
  workerDemandListeners: Set<(change: WorkerDemandChange) => void>;
  closedError: Error | null;
  logLevel: LogLevel;
  disposed: boolean;
  nextCoreId: number;
  coreWireSchemaHash: string | undefined;
}

function debugLoggingEnabled(state: RuntimeState): boolean {
  return state.logLevel === "debug" || state.logLevel === "trace";
}

let nextDisconnectRequestId = 0;
let nextPermissionAuthorizationRequestId = 0;
let nextSessionChatIdentityKeyRequestId = 0;
let nextDeviceEncryptionKeyRequestId = 0;
let nextProductSubtreePublicKeyRequestId = 0;
let nextSessionActivationRequestId = 0;
let nextActionRequestId = 0;
let nextRenderId = 0;

function encodePermissionAuthorizationRequest(
  request: PermissionAuthorizationRequest,
): Uint8Array {
  return PermissionAuthorizationRequestCodec.enc(request);
}

const DEV_LOG_LEVEL_KEY = "truapi:logLevel";

function readPersistedLogLevel(): LogLevel | null {
  return globalThis.localStorage?.getItem(DEV_LOG_LEVEL_KEY) ?? null;
}

// Dev-only, host-agnostic enablement for the wire debugger: in a DEV build, set
// `localStorage["truapi:debugger"] = "ws://<host>:9231"` in the browser and the
// host worker dials that debugger and streams frames to it. Read here (host page)
// and forwarded to the worker in `init`; no cooperation from the embedding shell.
const DEV_DEBUGGER_URL_KEY = "truapi:debugger";

/**
 * Why the wire debugger is (not) enabled, so a no-dial is never silent.
 *
 * `no-key` is the one that bites. The key is read on whichever origin creates the
 * runtime - the shell in an embedded host like dot.li, but an iframe realm in
 * another embedding - and `localStorage` is per-origin, so a key set anywhere else
 * is invisible here. Naming the origin is the whole point: the tap then stays dark
 * with nothing on screen to say why.
 */
type DebuggerEnablement = {
  readonly url: string | null;
  readonly reason:
    | "enabled"
    | "production-build"
    | "production-build-switch-set"
    | "no-key"
    | "no-storage";
};

function readPersistedDebuggerUrl(): DebuggerEnablement {
  // Hard dev-only gate, not a convention: bundlers (Vite) replace
  // `import.meta.env.DEV` with a boolean literal, so in a PRODUCTION build this
  // returns null unconditionally and the tap is inert - a stray localStorage key
  // cannot turn the debugger on in prod. The wire debugger streams raw
  // (now fully-decoded) frames and is strictly a development tool.
  //
  // The expression below must stay the *literal* `import.meta.env.DEV`, with no
  // alias and no optional chaining. A bundler replaces that exact token; reading
  // it through `const meta = import.meta` or as `import.meta.env?.DEV` does not
  // match, so the expression survives into the bundle and is evaluated at runtime
  // against an `import.meta.env` that a plain module does not have. That reads as
  // `undefined`, and the gate then refuses in *every* bundled host rather than
  // only production ones - which silently disables the standalone tap everywhere.
  // The try/catch keeps it safe where `import.meta.env` genuinely does not exist
  // (tsc output run under Node, unit tests), where the access throws.
  let dev = false;
  try {
    dev =
      (import.meta as unknown as { env: { DEV?: boolean } }).env.DEV === true;
  } catch {
    dev = false;
  }
  if (!dev) {
    // A switch set on a production build is someone actively trying to enable the
    // debugger against a build that cannot carry one. Distinguish it from plain
    // production so the reporter can say so: staying silent here is what makes a
    // compiled-out dial read as a broken debugger (design doc §9).
    //
    // Both the property access and the read sit inside the try. Reading the
    // `localStorage` PROPERTY is what throws (`SecurityError`) in a storage-denied
    // realm - a sandboxed iframe without `allow-same-origin`, or blocked
    // third-party storage - while `getItem` on an available store does not. This
    // function runs inside `createWebWorkerPairingHostRuntime`'s promise executor,
    // so an escaping throw rejects host creation over a debug-only lookup.
    let switchSet = false;
    try {
      const key = globalThis.localStorage?.getItem(DEV_DEBUGGER_URL_KEY);
      switchSet = key !== null && key !== undefined && key !== "";
    } catch {
      switchSet = false;
    }
    return {
      url: null,
      reason: switchSet ? "production-build-switch-set" : "production-build",
    };
  }
  const storage = globalThis.localStorage;
  if (storage === undefined) return { url: null, reason: "no-storage" };
  const url = storage.getItem(DEV_DEBUGGER_URL_KEY);
  if (url === null || url === "") return { url: null, reason: "no-key" };
  return { url, reason: "enabled" };
}

/**
 * Say once whether the debugger will dial - and from which origin. Silence here
 * used to be indistinguishable from a working tap: the debugger's own socket
 * count still moves (its UI holds one), so "connected but no frames" reads as a
 * debugger bug rather than a host that never dialled.
 *
 * Silent in a production build with the switch UNSET, where the message would be
 * noise. With the switch SET it says so once even in production: someone is
 * actively trying to enable a build that cannot carry the dial, and a host whose
 * only local build is production-mode (dot.li ships `build` and `preview`, no dev
 * server) otherwise gives them no signal at all. Design doc §9.
 */
function reportDebuggerEnablement(e: DebuggerEnablement): void {
  if (e.reason === "production-build") return;
  if (e.reason === "production-build-switch-set") {
    // Says "did not resolve true", not "this is a production build". The gate
    // cannot tell a production build from a bundler that never substituted the
    // token: both land on `dev === false`. Asserting production would tell a
    // developer on a genuine dev build under webpack/rollup/plain tsc to rebuild
    // in dev mode, which is the one configuration the comment above warns about.
    console.info(
      `[truapi] wire debugger: off (the "${DEV_DEBUGGER_URL_KEY}" switch is set, but ` +
        "`import.meta.env.DEV` did not resolve true, so the dial is compiled out. " +
        "Either this is a production build - rebuild the host in dev mode - or the " +
        "bundler did not substitute that token.",
    );
    return;
  }
  const origin = globalThis.location?.origin ?? "(unknown origin)";
  if (e.reason === "enabled") {
    console.info(
      `[truapi] wire debugger: dialling ${e.url} (origin ${origin})`,
    );
    return;
  }
  const why =
    e.reason === "no-storage"
      ? "no localStorage in this realm"
      : `no "${DEV_DEBUGGER_URL_KEY}" key on origin ${origin} - localStorage is ` +
        "per-origin, so set it on THIS origin (the realm that creates the host " +
        "runtime), then reload. A key on another origin is invisible here";
  console.info(`[truapi] wire debugger: off (${why})`);
}

function persistLogLevel(level: LogLevel): void {
  globalThis.localStorage?.setItem(DEV_LOG_LEVEL_KEY, level);
}

let devLogLevelOverride: LogLevel | null = readPersistedLogLevel();
const devGlobalTargets = new Set<{ setLogLevel?: (level: LogLevel) => void }>();
interface TrUApiDevConsole {
  setLogLevel(level: LogLevel): void;
  getLogLevel(): LogLevel | null;
}

function handleCallbackRequest(
  state: RuntimeState,
  msg: {
    requestId: number;
    name: CallbackName;
    args: readonly unknown[];
  },
): void {
  const fn = Object.hasOwn(state.rawCallbacks, msg.name)
    ? (
        state.rawCallbacks as unknown as Record<
          string,
          (...args: readonly unknown[]) => unknown
        >
      )[msg.name]
    : undefined;
  if (!fn) {
    state.worker.postMessage({
      kind: "callbackResponse",
      requestId: msg.requestId,
      ok: false,
      error: `unknown callback: ${msg.name}`,
    } satisfies MainToWorker);
    return;
  }
  Promise.resolve()
    .then(() => fn(...msg.args))
    .then(
      (value) => {
        state.worker.postMessage({
          kind: "callbackResponse",
          requestId: msg.requestId,
          ok: true,
          value,
        } satisfies MainToWorker);
      },
      (err) => {
        state.worker.postMessage({
          kind: "callbackResponse",
          requestId: msg.requestId,
          ok: false,
          error: errorMessage(err),
        } satisfies MainToWorker);
      },
    );
}

function handleSubscriptionStart(
  state: RuntimeState,
  msg: {
    subId: number;
    name: SubscriptionName;
    payload: Uint8Array | null;
  },
): void {
  const sendItem = (value?: unknown): void => {
    if (state.disposed) return;
    state.worker.postMessage({
      kind: "subscriptionItem",
      subId: msg.subId,
      value,
    } satisfies MainToWorker);
  };
  const sendError = (error: GenericError): void => {
    if (state.disposed) return;
    state.worker.postMessage({
      kind: "subscriptionError",
      subId: msg.subId,
      error: error.reason,
    } satisfies MainToWorker);
  };
  let dispose: (() => void) | void = undefined;
  try {
    dispose = startRawSubscription(
      state.rawCallbacks,
      msg.name,
      msg.payload,
      sendItem,
      sendError,
    );
  } catch (err) {
    console.error(`[truapi worker] ${msg.name} threw on start:`, err);
    return;
  }
  if (typeof dispose === "function") {
    state.subscriptionDisposers.set(msg.subId, dispose);
  }
}

function handleSubscriptionStop(
  state: RuntimeState,
  msg: { subId: number },
): void {
  const dispose = state.subscriptionDisposers.get(msg.subId);
  if (!dispose) return;
  state.subscriptionDisposers.delete(msg.subId);
  try {
    dispose();
  } catch (err) {
    console.warn("[truapi worker] subscription dispose threw:", err);
  }
}

async function handleChainConnectStart(
  state: RuntimeState,
  msg: { connId: number; genesisHash: string },
): Promise<void> {
  const chainConnect = state.rawCallbacks.chainConnect;
  const onResponse = (json: string): void => {
    if (state.disposed) return;
    state.worker.postMessage({
      kind: "chainResponse",
      connId: msg.connId,
      json,
    } satisfies MainToWorker);
  };
  try {
    const conn = await chainConnect(msg.genesisHash, onResponse);
    if (!conn) {
      state.worker.postMessage({
        kind: "chainConnectAck",
        connId: msg.connId,
        ok: false,
        error: `chainConnect returned null for genesisHash ${msg.genesisHash}`,
      } satisfies MainToWorker);
      return;
    }
    state.chainConnections.set(msg.connId, conn);
    state.worker.postMessage({
      kind: "chainConnectAck",
      connId: msg.connId,
      ok: true,
    } satisfies MainToWorker);
  } catch (err) {
    state.worker.postMessage({
      kind: "chainConnectAck",
      connId: msg.connId,
      ok: false,
      error: errorMessage(err),
    } satisfies MainToWorker);
  }
}

function handleChainSend(
  state: RuntimeState,
  msg: { connId: number; request: string },
): void {
  const conn = state.chainConnections.get(msg.connId);
  if (!conn) return;
  try {
    if (debugLoggingEnabled(state)) {
      console.debug("[truapi worker] chainSend", msg.connId, msg.request);
    }
    conn.send(msg.request);
  } catch (err) {
    console.warn("[truapi worker] chain send threw:", err);
  }
}

function handleChainClose(state: RuntimeState, msg: { connId: number }): void {
  const conn = state.chainConnections.get(msg.connId);
  if (!conn) return;
  state.chainConnections.delete(msg.connId);
  try {
    conn.close();
  } catch (err) {
    console.warn("[truapi worker] chain close threw:", err);
  }
}

interface PendingEntry<T> {
  resolve: (value: T) => void;
  reject: (error: Error) => void;
}

function settlePending<T>(
  map: Map<number, PendingEntry<T>>,
  requestId: number,
  result: { ok: true; value: T } | { ok: false; error: string },
): void {
  const pending = map.get(requestId);
  if (!pending) return;
  map.delete(requestId);
  if (result.ok) pending.resolve(result.value);
  else pending.reject(new Error(result.error));
}

function rejectAll<T>(map: Map<number, PendingEntry<T>>, error: Error): void {
  for (const pending of map.values()) {
    pending.reject(error);
  }
  map.clear();
}

function handleDisconnectResponse(
  state: RuntimeState,
  msg:
    | { requestId: number; ok: true }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingDisconnects,
    msg.requestId,
    msg.ok ? { ok: true, value: undefined } : { ok: false, error: msg.error },
  );
}

function handleSessionActivationResponse(
  state: RuntimeState,
  msg:
    | { requestId: number; ok: true }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingSessionActivations,
    msg.requestId,
    msg.ok ? { ok: true, value: undefined } : { ok: false, error: msg.error },
  );
}

function handlePermissionAuthorizationStatusResponse(
  state: RuntimeState,
  msg:
    | {
        requestId: number;
        ok: true;
        status: PermissionAuthorizationStatus;
      }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingPermissionAuthorizationStatuses,
    msg.requestId,
    msg.ok ? { ok: true, value: msg.status } : { ok: false, error: msg.error },
  );
}

function handlePermissionAuthorizationStatusesResponse(
  state: RuntimeState,
  msg:
    | {
        requestId: number;
        ok: true;
        statuses: PermissionAuthorizationStatus[];
      }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingPermissionAuthorizationStatusBatches,
    msg.requestId,
    msg.ok
      ? { ok: true, value: msg.statuses }
      : { ok: false, error: msg.error },
  );
}

function handleSetPermissionAuthorizationStatusResponse(
  state: RuntimeState,
  msg:
    | { requestId: number; ok: true }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingSetPermissionAuthorizationStatuses,
    msg.requestId,
    msg.ok ? { ok: true, value: undefined } : { ok: false, error: msg.error },
  );
}

function handleSessionChatIdentityKeyResponse(
  state: RuntimeState,
  msg:
    | { requestId: number; ok: true; key: Uint8Array | undefined }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingSessionChatIdentityKeys,
    msg.requestId,
    msg.ok ? { ok: true, value: msg.key } : { ok: false, error: msg.error },
  );
}

function handleProductSubtreePublicKeyResponse(
  state: RuntimeState,
  msg:
    | { requestId: number; ok: true; key: Uint8Array | undefined }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingProductSubtreePublicKeys,
    msg.requestId,
    msg.ok ? { ok: true, value: msg.key } : { ok: false, error: msg.error },
  );
}

function handleDeviceEncryptionKeyResponse(
  state: RuntimeState,
  msg:
    | { requestId: number; ok: true; key: Uint8Array }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingDeviceEncryptionKeys,
    msg.requestId,
    msg.ok ? { ok: true, value: msg.key } : { ok: false, error: msg.error },
  );
}

function rejectPendingRuntimeRequests(state: RuntimeState, error: Error): void {
  rejectAll(state.pendingDisconnects, error);
  rejectAll(state.pendingSessionActivations, error);
  rejectAll(state.pendingPermissionAuthorizationStatuses, error);
  rejectAll(state.pendingPermissionAuthorizationStatusBatches, error);
  rejectAll(state.pendingSetPermissionAuthorizationStatuses, error);
  rejectAll(state.pendingSessionChatIdentityKeys, error);
  rejectAll(state.pendingDeviceEncryptionKeys, error);
  rejectAll(state.pendingProductSubtreePublicKeys, error);
  rejectAll(state.pendingActions, error);
  for (const renderId of [...state.renders.keys()]) {
    const sink = takeRender(state, renderId);
    if (sink) reportRenderFailure(sink, error);
  }
  for (const pending of state.pendingCores.values()) {
    pending.reject(error);
  }
  state.pendingCores.clear();
}

function sendWorkerRequest<T>(
  state: RuntimeState,
  pending: Map<number, PendingEntry<T>>,
  nextId: () => number,
  disposedFallback: T,
  buildMessage: (requestId: number) => MainToWorker,
): Promise<T> {
  if (state.disposed) return Promise.resolve(disposedFallback);
  return new Promise((resolve, reject) => {
    const requestId = nextId();
    pending.set(requestId, { resolve, reject });
    try {
      state.worker.postMessage(buildMessage(requestId));
    } catch (err) {
      pending.delete(requestId);
      reject(err instanceof Error ? err : new Error(String(err)));
    }
  });
}

/**
 * Send a session activation request, rejecting rather than resolving when the
 * runtime is already gone. A host awaits these to learn whether it is signed
 * in, so a silent success after a worker fault would route it as if the
 * activation had run.
 */
function sendSessionActivationRequest(
  state: RuntimeState,
  buildMessage: (requestId: number) => MainToWorker,
): Promise<void> {
  if (state.disposed) {
    return Promise.reject(state.closedError ?? new Error("runtime disposed"));
  }
  return sendWorkerRequest<void>(
    state,
    state.pendingSessionActivations,
    () => ++nextSessionActivationRequestId,
    undefined,
    buildMessage,
  );
}

function closeCoreState(core: CoreState, error: Error): void {
  if (core.disposed) return;
  core.disposed = true;
  core.closedError = error;
  for (const listener of [...core.closeListeners]) listener(error);
  core.listeners.clear();
  core.closeListeners.clear();
}

function teardown(state: RuntimeState, error: Error, fault: boolean): void {
  if (state.disposed) return;
  state.disposed = true;
  state.closedError = error;
  rejectPendingRuntimeRequests(state, error);
  for (const core of state.cores.values()) {
    closeCoreState(core, error);
  }
  state.cores.clear();
  for (const fn of state.subscriptionDisposers.values()) {
    try {
      fn();
    } catch {
      // ignore during teardown
    }
  }
  state.subscriptionDisposers.clear();
  for (const conn of state.chainConnections.values()) {
    try {
      conn.close();
    } catch {
      // ignore during teardown
    }
  }
  state.chainConnections.clear();
  // A worker nothing can call any more is not wanted.
  for (const productId of [...state.wantedWorkers]) {
    handleWorkerDemandChanged(state, productId, false);
  }
  state.workerDemandListeners.clear();
  if (fault) {
    state.worker.terminate();
  } else {
    try {
      state.worker.postMessage({ kind: "dispose" } satisfies MainToWorker);
    } catch {
      // ignore if worker already gone
    }
    setTimeout(() => state.worker.terminate(), 0);
  }
}

export interface CreateWebWorkerPairingHostRuntimeOptions {
  logLevel?: LogLevel;
  hostConfig: WebWorkerHostConfig;
  initTimeoutMs?: number;
}

export type WebWorkerHostCallbacks = RequiredHostCallbacks;

export function createWebWorkerPairingHostRuntime(
  worker: Worker,
  host: WebWorkerHostCallbacks,
  options: CreateWebWorkerPairingHostRuntimeOptions,
): Promise<WorkerPairingHostRuntime> {
  const callbacks = createWasmRawCallbacks(host);

  return new Promise((resolve, reject) => {
    const state: RuntimeState = {
      worker,
      rawCallbacks: callbacks,
      cores: new Map(),
      pendingCores: new Map(),
      subscriptionDisposers: new Map(),
      chainConnections: new Map(),
      pendingDisconnects: new Map(),
      pendingSessionActivations: new Map(),
      pendingPermissionAuthorizationStatuses: new Map(),
      pendingPermissionAuthorizationStatusBatches: new Map(),
      pendingSetPermissionAuthorizationStatuses: new Map(),
      pendingSessionChatIdentityKeys: new Map(),
      pendingProductSubtreePublicKeys: new Map(),
      pendingDeviceEncryptionKeys: new Map(),
      pendingActions: new Map(),
      renders: new Map(),
      wantedWorkers: new Set(),
      workerDemandListeners: new Set(),
      closedError: null,
      logLevel: devLogLevelOverride ?? options.logLevel ?? "off",
      disposed: false,
      nextCoreId: 0,
      coreWireSchemaHash: undefined,
    };

    let runtime: WorkerPairingHostRuntime | null = null;

    const notifyFault = (error: Error): void => {
      teardown(state, error, true);
    };

    const onMessage = (ev: MessageEvent<WorkerToMain>): void => {
      const msg = ev.data;
      switch (msg.kind) {
        case "loaded":
        case "ready":
          break;
        case "coreReady":
          handleCoreReady(state, msg.coreId, runtime);
          break;
        case "coreError":
          handleCoreError(state, msg.coreId, msg.error);
          break;
        case "fatalError":
          console.error("[truapi worker]", msg.error);
          notifyFault(new Error(`worker fatal error: ${msg.error}`));
          break;
        case "frameError":
          handleFrameError(state, msg.coreId, msg.error);
          break;
        case "disposeError":
          console.warn("[truapi worker] dispose:", msg.error);
          break;
        case "frame": {
          const core = state.cores.get(msg.coreId);
          if (!core || core.disposed) break;
          if (debugLoggingEnabled(state)) {
            console.debug("[truapi worker] frame <-", bytesToHex(msg.bytes));
          }
          for (const listener of [...core.listeners]) listener(msg.bytes);
          break;
        }
        case "disconnectSessionResponse":
          handleDisconnectResponse(state, msg);
          break;
        case "sessionActivationResponse":
          handleSessionActivationResponse(state, msg);
          break;
        case "permissionAuthorizationStatusResponse":
          handlePermissionAuthorizationStatusResponse(state, msg);
          break;
        case "permissionAuthorizationStatusesResponse":
          handlePermissionAuthorizationStatusesResponse(state, msg);
          break;
        case "setPermissionAuthorizationStatusResponse":
          handleSetPermissionAuthorizationStatusResponse(state, msg);
          break;
        case "sessionChatIdentityKeyResponse":
          handleSessionChatIdentityKeyResponse(state, msg);
          break;
        case "deviceEncryptionKeyResponse":
          handleDeviceEncryptionKeyResponse(state, msg);
          break;
        case "productSubtreePublicKeyResponse":
          handleProductSubtreePublicKeyResponse(state, msg);
          break;
        case "workerDemandChanged":
          handleWorkerDemandChanged(state, msg.productId, msg.wanted);
          break;
        case "publishChatActionResponse":
        case "publishRendererActionResponse":
          settlePending(
            state.pendingActions,
            msg.requestId,
            msg.ok
              ? { ok: true, value: undefined }
              : { ok: false, error: msg.error },
          );
          break;
        case "renderItem": {
          const sink = state.renders.get(msg.renderId);
          if (!sink) break;
          // Escaping the listener would strand the render with no terminal.
          try {
            sink.onUpdate(RendererNodeCodec.dec(msg.node));
          } catch (err) {
            takeRender(state, msg.renderId);
            state.worker.postMessage({
              kind: "renderStop",
              renderId: msg.renderId,
            } satisfies MainToWorker);
            reportRenderFailure(sink, err);
          }
          break;
        }
        case "renderComplete": {
          const sink = takeRender(state, msg.renderId);
          try {
            sink?.onComplete();
          } catch (err) {
            console.warn("[truapi worker] render onComplete threw:", err);
          }
          break;
        }
        case "renderError": {
          const sink = takeRender(state, msg.renderId);
          if (sink) reportRenderFailure(sink, new Error(msg.error));
          break;
        }
        case "callbackRequest":
          if (debugLoggingEnabled(state)) {
            console.debug("[truapi worker] callbackRequest", msg.name);
          }
          handleCallbackRequest(state, msg);
          break;
        case "subscriptionStart":
          handleSubscriptionStart(state, msg);
          break;
        case "subscriptionStop":
          handleSubscriptionStop(state, msg);
          break;
        case "chainConnectStart":
          if (debugLoggingEnabled(state)) {
            console.debug("[truapi worker] chainConnectStart", msg.connId);
          }
          void handleChainConnectStart(state, msg);
          break;
        case "chainSend":
          handleChainSend(state, msg);
          break;
        case "chainClose":
          handleChainClose(state, msg);
          break;
        default: {
          const { kind } = msg as { kind?: unknown };
          console.warn(
            `[truapi worker] unknown worker message kind: ${String(kind)}`,
          );
        }
      }
    };

    const onError = (e: ErrorEvent): void => {
      cleanupInit();
      worker.terminate();
      reject(new Error(`worker init failed: ${e.message}`));
    };

    const onInitMessageError = (): void => {
      cleanupInit();
      worker.terminate();
      reject(new Error("worker message could not be deserialized during init"));
    };

    const onRuntimeError = (e: ErrorEvent): void => {
      console.error("[truapi worker]", e.message);
      notifyFault(new Error(`worker error: ${e.message}`));
    };

    const onMessageError = (): void => {
      notifyFault(new Error("worker message could not be deserialized"));
    };

    const debuggerEnablement = readPersistedDebuggerUrl();
    reportDebuggerEnablement(debuggerEnablement);

    const onInitMessage = (ev: MessageEvent<WorkerToMain>): void => {
      const msg = ev.data;
      if (msg.kind === "loaded") {
        worker.postMessage({
          kind: "init",
          logLevel: devLogLevelOverride ?? options.logLevel ?? "off",
          hostConfig: options.hostConfig,
          capabilities: {
            chat: host.chat !== undefined,
            permissionStatus: host.permissionStatus !== undefined,
          },
          debuggerUrl: debuggerEnablement.url,
        } satisfies MainToWorker);
      } else if (msg.kind === "ready") {
        state.coreWireSchemaHash = msg.schema;
        cleanupInit();
        worker.addEventListener("message", onMessage);
        worker.addEventListener("error", onRuntimeError);
        worker.addEventListener("messageerror", onMessageError);
        runtime = buildRuntime(state);
        exposeDevGlobal(runtime);
        resolve(runtime);
      } else if (msg.kind === "fatalError") {
        cleanupInit();
        worker.terminate();
        reject(new Error(`worker init reported error: ${msg.error}`));
      }
    };

    const cleanupInit = (): void => {
      clearTimeout(initTimeout);
      worker.removeEventListener("error", onError);
      worker.removeEventListener("messageerror", onInitMessageError);
      worker.removeEventListener("message", onInitMessage);
    };

    const timeoutMs = options.initTimeoutMs ?? 30_000;
    const initTimeout = setTimeout(() => {
      cleanupInit();
      worker.terminate();
      reject(new Error(`worker init timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    worker.addEventListener("error", onError);
    worker.addEventListener("messageerror", onInitMessageError);
    worker.addEventListener("message", onInitMessage);
  });
}

function handleCoreReady(
  state: RuntimeState,
  coreId: number,
  runtime: WorkerPairingHostRuntime | null,
): void {
  const pending = state.pendingCores.get(coreId);
  if (!pending || !runtime) return;
  state.pendingCores.delete(coreId);
  const core: CoreState = {
    coreId,
    productId: pending.productId,
    listeners: new Set(),
    closeListeners: new Set(),
    closedError: null,
    disposed: false,
  };
  state.cores.set(coreId, core);
  pending.resolve(buildProvider(state, core, runtime));
}

function handleCoreError(
  state: RuntimeState,
  coreId: number,
  error: string,
): void {
  const pending = state.pendingCores.get(coreId);
  if (!pending) return;
  state.pendingCores.delete(coreId);
  pending.reject(new Error(error));
}

function handleFrameError(
  state: RuntimeState,
  coreId: number,
  error: string,
): void {
  console.error("[truapi worker]", error);
  const core = state.cores.get(coreId);
  if (!core) return;
  const failure = new Error(`worker frame error: ${error}`);
  closeCoreState(core, failure);
  state.cores.delete(coreId);
  // Renders left registered would never settle: the worker cancels them with
  // the core, so nothing further arrives to complete the sink.
  failRendersForCore(state, coreId, failure);
  try {
    state.worker.postMessage({
      kind: "disposeCore",
      coreId,
    } satisfies MainToWorker);
  } catch {
    // ignore if worker is already gone
  }
}

function buildRuntime(state: RuntimeState): WorkerPairingHostRuntime {
  const runtime: WorkerPairingHostRuntime = {
    coreWireSchemaHash: state.coreWireSchemaHash,
    createProvider(product): Promise<TrUApiProductProvider> {
      if (state.disposed) {
        return Promise.reject(
          state.closedError ?? new Error("runtime disposed"),
        );
      }
      return new Promise((resolve, reject) => {
        const coreId = ++state.nextCoreId;
        state.pendingCores.set(coreId, {
          productId: product.productId,
          resolve,
          reject,
        });
        try {
          state.worker.postMessage({
            kind: "createCore",
            coreId,
            product,
          } satisfies MainToWorker);
        } catch (err) {
          state.pendingCores.delete(coreId);
          reject(err instanceof Error ? err : new Error(String(err)));
        }
      });
    },
    disconnectSession(): Promise<void> {
      return sendWorkerRequest<void>(
        state,
        state.pendingDisconnects,
        () => ++nextDisconnectRequestId,
        undefined,
        (requestId) => ({ kind: "disconnectSession", requestId }),
      );
    },
    cancelPairing(): void {
      if (state.disposed) return;
      state.worker.postMessage({
        kind: "cancelPairing",
      } satisfies MainToWorker);
    },
    getSessionChatIdentityKey(): Promise<Uint8Array | undefined> {
      return sendWorkerRequest<Uint8Array | undefined>(
        state,
        state.pendingSessionChatIdentityKeys,
        () => ++nextSessionChatIdentityKeyRequestId,
        undefined,
        (requestId) => ({ kind: "getSessionChatIdentityKey", requestId }),
      );
    },
    getDeviceEncryptionKey(): Promise<Uint8Array> {
      // A key has no safe empty value: callers encrypt with what they get back,
      // so a disposed runtime must fail rather than hand out a zero-length one.
      // The check is synchronous with the send, so the fallback is unreachable.
      if (state.disposed) {
        return Promise.reject(new Error("worker host runtime is disposed"));
      }
      return sendWorkerRequest<Uint8Array>(
        state,
        state.pendingDeviceEncryptionKeys,
        () => ++nextDeviceEncryptionKeyRequestId,
        new Uint8Array(),
        (requestId) => ({ kind: "getDeviceEncryptionKey", requestId }),
      );
    },
    getProductSubtreePublicKey(
      productId: string,
      timeoutMs?: number,
    ): Promise<Uint8Array | undefined> {
      return sendWorkerRequest<Uint8Array | undefined>(
        state,
        state.pendingProductSubtreePublicKeys,
        () => ++nextProductSubtreePublicKeyRequestId,
        undefined,
        (requestId) => ({
          kind: "getProductSubtreePublicKey",
          requestId,
          productId,
          timeoutMs,
        }),
      );
    },
    notifySessionStoreChanged(): void {
      if (state.disposed) return;
      state.worker.postMessage({
        kind: "notifySessionStoreChanged",
      } satisfies MainToWorker);
    },
    acquireWorker(productId: string): void {
      postUnlessDisposed(state, { kind: "acquireWorker", productId });
    },
    releaseWorker(productId: string): void {
      postUnlessDisposed(state, { kind: "releaseWorker", productId });
    },
    subscribeWorkerDemand(listener) {
      state.workerDemandListeners.add(listener);
      for (const productId of state.wantedWorkers) {
        listener({ productId, wanted: true });
      }
      return () => {
        state.workerDemandListeners.delete(listener);
      };
    },
    activateStoredSession(): Promise<void> {
      return sendSessionActivationRequest(state, (requestId) => ({
        kind: "activateStoredSession",
        requestId,
      }));
    },
    activateExternalSession(blob: Uint8Array): Promise<void> {
      return sendSessionActivationRequest(state, (requestId) => ({
        kind: "activateExternalSession",
        requestId,
        blob,
      }));
    },
    resetSessionState(): Promise<void> {
      return sendSessionActivationRequest(state, (requestId) => ({
        kind: "resetSessionState",
        requestId,
      }));
    },
    getPermissionAuthorizationStatus(productId, request) {
      return sendWorkerRequest<PermissionAuthorizationStatus>(
        state,
        state.pendingPermissionAuthorizationStatuses,
        () => ++nextPermissionAuthorizationRequestId,
        "NotDetermined",
        (requestId) => ({
          kind: "getPermissionAuthorizationStatus",
          productId,
          requestId,
          request: encodePermissionAuthorizationRequest(request),
        }),
      );
    },
    getPermissionAuthorizationStatuses(productId, requests) {
      return sendWorkerRequest<PermissionAuthorizationStatus[]>(
        state,
        state.pendingPermissionAuthorizationStatusBatches,
        () => ++nextPermissionAuthorizationRequestId,
        requests.map(() => "NotDetermined"),
        (requestId) => ({
          kind: "getPermissionAuthorizationStatuses",
          productId,
          requestId,
          requests: requests.map(encodePermissionAuthorizationRequest),
        }),
      );
    },
    setPermissionAuthorizationStatus(productId, request, status) {
      return sendWorkerRequest<void>(
        state,
        state.pendingSetPermissionAuthorizationStatuses,
        () => ++nextPermissionAuthorizationRequestId,
        undefined,
        (requestId) => ({
          kind: "setPermissionAuthorizationStatus",
          productId,
          requestId,
          request: encodePermissionAuthorizationRequest(request),
          status,
        }),
      );
    },
    setLogLevel(level): void {
      if (state.disposed) return;
      state.logLevel = level;
      state.worker.postMessage({
        kind: "setLogLevel",
        level,
      } satisfies MainToWorker);
    },
    dispose(): void {
      devGlobalTargets.delete(runtime);
      teardown(state, new Error("runtime disposed"), false);
    },
  };
  return runtime;
}

/** Post a fire-and-forget control message; a disposed runtime drops it. */
function postUnlessDisposed(state: RuntimeState, message: MainToWorker): void {
  if (state.disposed) return;
  state.worker.postMessage(message);
}

/** Record one product's wanted level and fan it out to every listener. */
function handleWorkerDemandChanged(
  state: RuntimeState,
  productId: string,
  wanted: boolean,
): void {
  if (wanted) state.wantedWorkers.add(productId);
  else state.wantedWorkers.delete(productId);
  for (const listener of state.workerDemandListeners) {
    try {
      listener({ productId, wanted });
    } catch (err) {
      console.warn("[truapi worker] worker demand listener threw:", err);
    }
  }
}

/** Deliver a render failure without letting the sink's own throw escape. */
function reportRenderFailure(
  sink: { onError: (error: Error) => void },
  cause: unknown,
): void {
  try {
    sink.onError(
      cause instanceof Error ? cause : new Error(errorMessage(cause)),
    );
  } catch (err) {
    console.warn("[truapi worker] render onError threw:", err);
  }
}

/**
 * Drop one render from the ledger. Returns the sink so the caller can settle
 * it, and undefined once the render is already gone, which is what keeps a
 * render settled exactly once.
 */
function takeRender(
  state: RuntimeState,
  renderId: number,
): RenderEntry | undefined {
  const entry = state.renders.get(renderId);
  if (!entry) return undefined;
  state.renders.delete(renderId);
  return entry;
}

/** Settle and drop every render belonging to one product connection. */
function failRendersForCore(
  state: RuntimeState,
  coreId: number,
  error: Error,
): void {
  for (const [renderId, entry] of [...state.renders]) {
    if (entry.coreId !== coreId) continue;
    const sink = takeRender(state, renderId);
    if (sink) reportRenderFailure(sink, error);
  }
}

/**
 * Post one host-authored action to the worker and settle on its response.
 * Encoding runs before the pending entry exists, so a payload the codec
 * rejects fails the promise without leaving one behind.
 */
function publishAction(
  state: RuntimeState,
  core: CoreState,
  kind: "publishChatAction" | "publishRendererAction",
  encode: () => Uint8Array,
): Promise<void> {
  if (state.disposed || core.disposed) {
    return Promise.reject(new Error("product connection is closed"));
  }
  let action: Uint8Array;
  try {
    action = encode();
  } catch (err) {
    return Promise.reject(toError(err));
  }
  return sendWorkerRequest<void>(
    state,
    state.pendingActions,
    () => nextActionRequestId++,
    undefined,
    (requestId) => ({ kind, coreId: core.coreId, requestId, action }),
  );
}

function buildProvider(
  state: RuntimeState,
  core: CoreState,
  runtime: WorkerPairingHostRuntime,
): TrUApiProductProvider {
  const provider: TrUApiProductProvider = {
    postMessage(bytes: Uint8Array): void {
      if (state.disposed || core.disposed) return;
      if (debugLoggingEnabled(state)) {
        console.debug("[truapi worker] frame ->", bytesToHex(bytes));
      }
      state.worker.postMessage({
        kind: "frame",
        coreId: core.coreId,
        bytes,
      } satisfies MainToWorker);
    },
    subscribe(callback) {
      core.listeners.add(callback);
      return () => {
        core.listeners.delete(callback);
      };
    },
    subscribeClose(callback) {
      const closed = core.closedError ?? state.closedError;
      if (closed) {
        callback(closed);
        return () => {};
      }
      core.closeListeners.add(callback);
      return () => {
        core.closeListeners.delete(callback);
      };
    },
    disconnectSession(): Promise<void> {
      if (core.disposed) return Promise.resolve();
      return runtime.disconnectSession();
    },
    async getSessionChatIdentityKey(): Promise<Bytes32 | undefined> {
      if (core.disposed) return undefined;
      const key = await runtime.getSessionChatIdentityKey();
      return key && bytesToHex(key);
    },
    async getDeviceEncryptionKey(): Promise<Bytes32> {
      if (core.disposed) {
        throw new Error("product connection is closed");
      }
      return bytesToHex(await runtime.getDeviceEncryptionKey());
    },
    async getProductSubtreePublicKey(
      productId: string,
      timeoutMs?: number,
    ): Promise<Bytes32 | undefined> {
      if (core.disposed) return undefined;
      const key = await runtime.getProductSubtreePublicKey(
        productId,
        timeoutMs,
      );
      return key && bytesToHex(key);
    },
    getPermissionAuthorizationStatus(request) {
      if (core.disposed) return Promise.resolve("NotDetermined");
      return runtime.getPermissionAuthorizationStatus(core.productId, request);
    },
    getPermissionAuthorizationStatuses(requests) {
      if (core.disposed) {
        return Promise.resolve(requests.map(() => "NotDetermined"));
      }
      return runtime.getPermissionAuthorizationStatuses(
        core.productId,
        requests,
      );
    },
    setPermissionAuthorizationStatus(request, status) {
      if (core.disposed) return Promise.resolve();
      return runtime.setPermissionAuthorizationStatus(
        core.productId,
        request,
        status,
      );
    },
    setLogLevel(level): void {
      if (core.disposed) return;
      runtime.setLogLevel(level);
    },
    publishChatAction(action: HostChatActionSubscribeItem): Promise<void> {
      return publishAction(state, core, "publishChatAction", () =>
        HostChatActionSubscribeItemCodec.enc(action),
      );
    },
    publishRendererAction(
      item: HostRendererActionSubscribeItem,
    ): Promise<void> {
      return publishAction(state, core, "publishRendererAction", () =>
        HostRendererActionSubscribeItemCodec.enc(item),
      );
    },
    render(request, sink) {
      if (state.disposed || core.disposed) {
        sink.onError?.(new Error("product connection is closed"));
        return () => {};
      }
      // Encode before the ledger entry exists, so a request the codec rejects
      // reaches the sink as an error rather than escaping `render` and leaving
      // a render registered that the worker was never told about.
      let encoded: Uint8Array;
      try {
        encoded = ProductRendererRenderRequestCodec.enc(request);
      } catch (err) {
        reportRenderFailure({ onError: (error) => sink.onError?.(error) }, err);
        return () => {};
      }
      const renderId = nextRenderId++;
      // The core holds the worker reference an open render is worth, and
      // reports every demand transition through `workerDemandChanged`.
      state.renders.set(renderId, {
        coreId: core.coreId,
        onUpdate: (node) => sink.onUpdate(node),
        onComplete: () => sink.onComplete?.(),
        onError: (error) => sink.onError?.(error),
      });
      state.worker.postMessage({
        kind: "renderStart",
        coreId: core.coreId,
        renderId,
        request: encoded,
      } satisfies MainToWorker);
      return () => {
        if (!takeRender(state, renderId)) return;
        state.worker.postMessage({
          kind: "renderStop",
          renderId,
        } satisfies MainToWorker);
      };
    },
    dispose(): void {
      if (core.disposed) return;
      closeCoreState(core, new Error("provider disposed"));
      state.cores.delete(core.coreId);
      // Renders left registered would never settle: the worker cancels them
      // with the core, so nothing further arrives to complete the sink.
      failRendersForCore(state, core.coreId, new Error("provider disposed"));
      state.worker.postMessage({
        kind: "disposeCore",
        coreId: core.coreId,
      } satisfies MainToWorker);
    },
  };
  return provider;
}

function exposeDevGlobal(target: {
  setLogLevel?: (level: LogLevel) => void;
}): void {
  devGlobalTargets.add(target);
  if (devLogLevelOverride !== null) {
    target.setLogLevel?.(devLogLevelOverride);
  }
  publishDevGlobal();
}

function publishDevGlobal(): void {
  const target = globalThis as {
    __truapi?: TrUApiDevConsole;
  };
  target.__truapi = {
    setLogLevel(level: LogLevel): void {
      devLogLevelOverride = level;
      persistLogLevel(level);
      for (const provider of [...devGlobalTargets]) {
        provider.setLogLevel?.(level);
      }
      console.info(`[truapi worker] logLevel=${level}`);
    },
    getLogLevel(): LogLevel | null {
      return devLogLevelOverride;
    },
  };
}

publishDevGlobal();
