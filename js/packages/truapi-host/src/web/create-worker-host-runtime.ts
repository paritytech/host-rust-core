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
import { isLoopbackWsUrl } from "../worker-protocol.js";
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
  getDeviceStatementKey(): Promise<Uint8Array | undefined>;
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
  pendingDeviceStatementKeys: Map<
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
let nextDeviceStatementKeyRequestId = 0;
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

/**
 * Why the wire debugger is (not) enabled, so a no-dial is never silent.
 *
 * There is no browser store in this path, and no runtime switch. The dial is
 * something the embedding host passes in (`options.debugger`), with the value a
 * dev build was compiled with as the default, and it is resolved once.
 * A library reading a key out of `localStorage` behind its embedder was both
 * un-turn-off-able from the host's own UI and invisible across origins and
 * browser profiles, which is what made a dark tap so hard to explain.
 */
export type DebuggerEnablement = {
  readonly url: string | null;
  readonly reason:
    | "enabled-from-option"
    | "enabled-from-build"
    | "production-build"
    | "production-build-configured"
    | "refused-not-loopback"
    | "not-configured";
};

/**
 * Dial URL a dev build was compiled with, when it was given one.
 *
 * This is the default, not the mechanism: it lets `make debugger` hand a whole
 * local stack a working tap with nothing to switch on, in any browser profile.
 * An embedder that passes `debugger` explicitly overrides it.
 *
 * Same literal-token rule as the `DEV` read below: a bundler replaces the exact
 * `import.meta.env.VITE_TRUAPI_DEBUGGER_URL` expression, so it must not be aliased or
 * optionally chained. The try/catch covers realms with no `import.meta.env` at all
 * (tsc output under Node, unit tests), where the access throws.
 */
function buildTimeDebuggerUrl(): string | null {
  let raw: unknown;
  try {
    raw = (
      import.meta as unknown as { env: { VITE_TRUAPI_DEBUGGER_URL?: unknown } }
    ).env.VITE_TRUAPI_DEBUGGER_URL;
  } catch {
    return null;
  }
  if (typeof raw !== "string") return null;
  const url = raw.trim();
  return url === "" ? null : url;
}

/**
 * Whether this build may carry a wire tap at all.
 *
 * Hard dev-only gate, not a convention: bundlers (Vite) replace
 * `import.meta.env.DEV` with a boolean literal, so a PRODUCTION build returns
 * false unconditionally, no option can turn the debugger on, and the tap is never
 * installed. The wire debugger streams fully-decoded frames and is strictly a
 * development tool.
 *
 * The expression below must stay the *literal* `import.meta.env.DEV`, with no
 * alias and no optional chaining. A bundler replaces that exact token; reading it
 * through `const meta = import.meta` or as `import.meta.env?.DEV` does not match,
 * so the expression survives into the bundle and is evaluated at runtime against
 * an `import.meta.env` that a plain module does not have. That reads as
 * `undefined`, and the gate then refuses in *every* bundled host rather than only
 * production ones - which silently disables the tap everywhere. The try/catch
 * keeps it safe where `import.meta.env` genuinely does not exist (tsc output run
 * under Node, unit tests), where the access throws.
 */
function debuggerBuildAllows(): boolean {
  try {
    return (
      (import.meta as unknown as { env: { DEV?: boolean } }).env.DEV === true
    );
  } catch {
    return false;
  }
}

/**
 * Which of the two production verdicts applies. Pure, and exported for the same
 * reason {@link resolveDebuggerEnablement} is: the caller reads
 * `import.meta.env`, which a bundler substitutes and a test runner cannot, so
 * neither the build value nor the DEV gate can be varied from a test.
 *
 * The build half is the one that matters and the one that is easy to drop. The
 * env var is substituted at build time, so it is still readable in a production
 * bundle - a build made with it but without `NODE_ENV=development` is exactly the
 * case that must not go quiet. An option, by contrast, is passed by a host that is
 * still running, so it is visible either way.
 */
export function productionReason(
  fromOption: string | null | undefined,
  fromBuild: string | null,
): "production-build" | "production-build-configured" {
  const asked =
    fromBuild !== null || (typeof fromOption === "string" && fromOption !== "");
  return asked ? "production-build-configured" : "production-build";
}

function readDebuggerEnablement(
  fromOption: string | null | undefined,
): DebuggerEnablement {
  const fromBuild = buildTimeDebuggerUrl();
  if (!debuggerBuildAllows()) {
    // Somebody asked for a dial this build cannot carry. Saying nothing here is
    // the failure design doc §9 exists to prevent: the easiest way to reach it is
    // to copy the build command and drop `NODE_ENV=development`, and what you get
    // is an empty board, no console line, and no error - which reads as a broken
    // debugger rather than a build that compiled the dial out.
    //
    // Keyed on the BUILD value as well as the option, because the build value is
    // the half that survives into a production bundle: the env var is substituted
    // at build time, so it is still readable here, while an option passed by a
    // host is not something this branch can see going unused.
    return { url: null, reason: productionReason(fromOption, fromBuild) };
  }
  return resolveDebuggerEnablement(fromOption, fromBuild);
}

/**
 * Resolve the dev-build switches into one verdict. Pure, and exported so the
 * precedence is testable: the caller reads `import.meta.env.DEV`, which a bundler
 * substitutes and a test runner cannot, so the live path cannot reach this branch
 * under `bun test` at all.
 *
 * `fromOption` is `undefined` when the embedder said nothing, `null` or `""` when
 * it explicitly asked for no dial, and a URL when it asked for one.
 *
 * Precedence:
 *
 *  - option set to a URL  -> dial it, whatever the build says
 *  - option set null/""   -> OFF, whatever the build says
 *  - option omitted       -> the build's value, if it carries one
 *
 * The explicit-off case is the one that is easy to get wrong: folding `null` in
 * with "omitted" falls through to the build, and an embedder that compiled a URL
 * in then has no way to refuse the dial short of rebuilding.
 *
 * A resolved URL is loopback `ws://` or it is refused (§6). The worker builds an
 * inert link for anything else, so resolving one as enabled would report a dial
 * that never carries a frame - the silent-tap failure §9 exists to prevent, with
 * the host's own log and badge naming an endpoint nothing streams to.
 */
export function resolveDebuggerEnablement(
  fromOption: string | null | undefined,
  fromBuild: string | null,
): DebuggerEnablement {
  if (fromOption === null || fromOption === "")
    return { url: null, reason: "not-configured" };
  if (typeof fromOption === "string")
    return refuseUnlessLoopback(fromOption, "enabled-from-option");
  if (fromBuild !== null)
    return refuseUnlessLoopback(fromBuild, "enabled-from-build");
  return { url: null, reason: "not-configured" };
}

/** Let `url` through under `reason`, or refuse it for not being loopback `ws://`. */
function refuseUnlessLoopback(
  url: string,
  reason: "enabled-from-option" | "enabled-from-build",
): DebuggerEnablement {
  if (!isLoopbackWsUrl(url))
    return { url: null, reason: "refused-not-loopback" };
  return { url, reason };
}

/**
 * Say once whether the debugger will dial - and from which origin. Silence here
 * used to be indistinguishable from a working tap: the debugger's own socket
 * count still moves (its UI holds one), so "connected but no frames" reads as a
 * debugger bug rather than a host that never dialled.
 *
 * Silent in a production build, where the message would be noise and there is
 * nothing a developer could do about it in that build anyway.
 */
function reportDebuggerEnablement(e: DebuggerEnablement): void {
  if (e.reason === "production-build") return;
  if (e.reason === "production-build-configured") {
    // Says "did not resolve true", not "this is a production build". The gate
    // cannot tell the two apart: a genuine production build and a bundler that
    // never substituted the token both leave the condition false, and asserting
    // production would send a developer on a dev build under webpack or plain
    // tsc off to rebuild in dev mode - the one case that would not help.
    console.info(
      "[truapi] wire debugger: off (a dial was configured, but " +
        "`import.meta.env.DEV` did not resolve true, so the tap is compiled out. " +
        "Either this is a production build - rebuild the host in dev mode - or " +
        "the bundler did not substitute that token.",
    );
    return;
  }
  const origin = globalThis.location?.origin ?? "(unknown origin)";
  if (e.reason === "enabled-from-option") {
    console.info(
      `[truapi] wire debugger: dialling ${e.url} from the host's option (origin ${origin})`,
    );
    return;
  }
  if (e.reason === "enabled-from-build") {
    console.info(
      `[truapi] wire debugger: dialling ${e.url} from the build (origin ${origin})`,
    );
    return;
  }
  if (e.reason === "refused-not-loopback") {
    console.warn(
      "[truapi] wire debugger: off (the configured dial is not a `ws://` URL on a " +
        "loopback host, so it was refused. The tap forwards frames verbatim, " +
        `payloads included, and never leaves this machine.) on origin ${origin}`,
    );
    return;
  }
  console.info(
    "[truapi] wire debugger: off (this host passed no `debugger` option and the " +
      `build carries no VITE_TRUAPI_DEBUGGER_URL) on origin ${origin}`,
  );
}

function persistLogLevel(level: LogLevel): void {
  globalThis.localStorage?.setItem(DEV_LOG_LEVEL_KEY, level);
}

let devLogLevelOverride: LogLevel | null = readPersistedLogLevel();
const devGlobalTargets = new Set<{ setLogLevel?: (level: LogLevel) => void }>();
/**
 * Deliberately carries no debugger control. The dial is decided once, by the
 * build or by the host, so whether frames are leaving is a property of how this
 * bundle was made rather than of something typed into a console afterwards. A
 * runtime toggle would also give console-paste - a live pattern against wallet
 * users - something worth pasting at.
 */
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

function handleDeviceStatementKeyResponse(
  state: RuntimeState,
  msg:
    | { requestId: number; ok: true; key: Uint8Array | undefined }
    | { requestId: number; ok: false; error: string },
): void {
  settlePending(
    state.pendingDeviceStatementKeys,
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
  rejectAll(state.pendingDeviceStatementKeys, error);
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
  releaseDebuggerDial(state);
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
  /**
   * Dev-only: a loopback `ws://` wire debugger to stream tapped frames to.
   *
   * The host decides. Omit the field to take whatever the build was compiled with
   * (`VITE_TRUAPI_DEBUGGER_URL`, which is how `make debugger` hands a local stack a
   * working tap with nothing to switch on); pass `null` or `""` to refuse the dial
   * even when the build carries one.
   *
   * Ignored outside a dev build: the `import.meta.env.DEV` gate refuses first, so
   * a production bundle cannot be talked into a tap by any value here.
   *
   * Resolved once, when the runtime is created, and not changeable from the
   * page afterwards: whether this host streams frames is a property of the
   * build and of what the host asked for, nothing later.
   */
  debugger?: string | null;
  /**
   * Dev-only: whether to show the built-in indicator while a dial is live.
   *
   * Defaults to `true`. Pass `false` only when this host renders its own visible
   * signal - the point is that a tap streaming frames off this host is never
   * invisible, not that this particular badge is used.
   */
  debuggerIndicator?: boolean;
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
      pendingDeviceStatementKeys: new Map(),
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
        case "deviceStatementKeyResponse":
          handleDeviceStatementKeyResponse(state, msg);
          break;
        case "deviceEncryptionKeyResponse":
          handleDeviceEncryptionKeyResponse(state, msg);
          break;
        case "productSubtreePublicKeyResponse":
          handleProductSubtreePublicKeyResponse(state, msg);
          break;
        case "workerDemandChanged":
          // Teardown has already reported every worker unwanted, so a level
          // still in flight would put one back that nothing can serve.
          if (!state.disposed) {
            handleWorkerDemandChanged(state, msg.productId, msg.wanted);
          }
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

    // The tap exists for this session exactly when a dial was resolved, and that
    // is decided here, once. With no attach-later path there is no second piece
    // of state to keep in step - which is what let an earlier
    // `reason !== "production-build"` test arm a production build carrying a URL.
    const debuggerDial = installDebuggerDial(
      state,
      readDebuggerEnablement(options.debugger),
      options.debuggerIndicator,
    );

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
            pocket: host.pocket !== undefined,
          },
          debuggerUrl: debuggerDial,
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
    getDeviceStatementKey(): Promise<Uint8Array | undefined> {
      return sendWorkerRequest<Uint8Array | undefined>(
        state,
        state.pendingDeviceStatementKeys,
        () => ++nextDeviceStatementKeyRequestId,
        undefined,
        (requestId) => ({ kind: "getDeviceStatementKey", requestId }),
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
      // Teardown cleared the listeners, so one added now would only be
      // retained, never called.
      if (state.disposed) return () => {};
      state.workerDemandListeners.add(listener);
      for (const productId of state.wantedWorkers) {
        deliverWorkerDemand(listener, { productId, wanted: true });
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

/** Hand one change to one listener, keeping its throw off the caller. */
function deliverWorkerDemand(
  listener: (change: WorkerDemandChange) => void,
  change: WorkerDemandChange,
): void {
  try {
    listener(change);
  } catch (err) {
    console.warn("[truapi worker] worker demand listener threw:", err);
  }
}

/** Record one product's wanted level and fan it out to every listener. */
function handleWorkerDemandChanged(
  state: RuntimeState,
  productId: string,
  wanted: boolean,
): void {
  if (wanted) state.wantedWorkers.add(productId);
  else state.wantedWorkers.delete(productId);
  // Delivery runs over a snapshot, and skips anyone no longer subscribed when
  // their turn comes: a listener that subscribes from inside a listener has
  // already had this change replayed to it, and one that unsubscribes, or
  // disposes the runtime, must hear nothing further.
  for (const listener of [...state.workerDemandListeners]) {
    if (!state.workerDemandListeners.has(listener)) continue;
    deliverWorkerDemand(listener, { productId, wanted });
  }
}

/** Deliver a render failure without letting the sink's own throw escape. */
function reportRenderFailure(
  sink: { onError?: (error: Error) => void },
  cause: unknown,
): void {
  try {
    sink.onError?.(toError(cause));
  } catch (err) {
    console.warn("[truapi worker] render onError threw:", err);
  }
}

/**
 * Drop one render from the ledger, returning its sink only the first time,
 * which is what keeps a render settled exactly once.
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
 * Encoding runs before registering, so a payload the codec rejects leaves no
 * pending entry behind.
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
    async getDeviceStatementKey(): Promise<Uint8Array | undefined> {
      if (core.disposed) return undefined;
      return runtime.getDeviceStatementKey();
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
      // Encode before registering, so a request the codec rejects leaves no
      // render behind that the worker was never told about.
      let encoded: Uint8Array;
      try {
        encoded = ProductRendererRenderRequestCodec.enc(request);
      } catch (err) {
        reportRenderFailure(sink, err);
        return () => {};
      }
      const renderId = nextRenderId++;
      // No worker reference is taken here: the core holds the one an open
      // render is worth and reports it through `workerDemandChanged`.
      state.renders.set(renderId, {
        coreId: core.coreId,
        onUpdate: (node) => sink.onUpdate(node),
        onComplete: () => sink.onComplete?.(),
        onError: (error) => sink.onError?.(error),
      });
      try {
        state.worker.postMessage({
          kind: "renderStart",
          coreId: core.coreId,
          renderId,
          request: encoded,
        } satisfies MainToWorker);
      } catch (err) {
        const failed = takeRender(state, renderId);
        if (failed) reportRenderFailure(failed, err);
        return () => {};
      }
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

/** Element id of the dial indicator, so a re-render finds the existing node. */
const DEBUGGER_INDICATOR_ID = "truapi-debugger-indicator";

/**
 * The endpoint every live dial is streaming to, keyed by the runtime that owns
 * it.
 *
 * The badge is a single node at a fixed id, while an embedder may create one
 * worker runtime per product surface and give only some of them a dial. Keyed
 * ownership is what keeps a runtime with no dial, or one that renders its own
 * signal, from taking down a badge another runtime's tap is still behind, and
 * what lets two live dials both be named instead of the later one hiding the
 * earlier.
 */
const liveDebuggerDials = new Map<object, string>();

/**
 * Put `owner`'s debugger dial into service: say once whether it will dial, show
 * the endpoint in the page for as long as it does, and hand back the URL the
 * worker's `init` message carries.
 *
 * The three are one decision, so they are one function: a host that resolves a
 * dial and then reports, badges or forwards something else is the failure the
 * design doc's §9 is about. Taking the already-resolved enablement as an
 * argument is what makes that decision testable at all, since the live caller
 * reads `import.meta.env.DEV`, which a bundler substitutes and a test runner
 * cannot, so a test driving the runtime only ever sees the production verdict.
 */
export function installDebuggerDial(
  owner: object,
  enablement: DebuggerEnablement,
  indicator: boolean | undefined,
): string | null {
  reportDebuggerEnablement(enablement);
  if (enablement.url !== null && indicator !== false)
    liveDebuggerDials.set(owner, enablement.url);
  else liveDebuggerDials.delete(owner);
  paintDebuggerIndicator();
  return enablement.url;
}

/**
 * Take `owner`'s dial out of service. Its worker is gone, so nothing streams on
 * its account any more, and a badge naming an endpoint no frame reaches is the
 * silent-tap failure read backwards.
 */
export function releaseDebuggerDial(owner: object): void {
  if (!liveDebuggerDials.delete(owner)) return;
  paintDebuggerIndicator();
}

/**
 * Show, in the page, that wire frames are leaving this host, naming every
 * endpoint they leave for.
 *
 * A console line is not enough on its own: it scrolls away, and a tap left on
 * from an earlier session is then invisible for the rest of the day. Loopback
 * makes that cheap today, but the dial is the thing that would carry decoded
 * frames off the machine if it ever pointed anywhere else, so it should be
 * something you can SEE is on.
 *
 * Default-on rather than opt-in, because the failure being prevented is a host
 * forgetting. A host that renders its own affordance passes
 * `debuggerIndicator: false` and takes the job on.
 *
 * Dev-only by construction: a dial only reaches {@link liveDebuggerDials} when
 * the `import.meta.env.DEV` gate resolved one, so a production bundle never
 * mounts this. Never throws - a host must not fail to start because a debug
 * badge could not render.
 */
function paintDebuggerIndicator(): void {
  try {
    const doc = globalThis.document;
    if (doc === undefined || doc.body === null) return;
    const existing = doc.getElementById(DEBUGGER_INDICATOR_ID);
    const endpoints = [...new Set(liveDebuggerDials.values())];
    if (endpoints.length === 0) {
      existing?.remove();
      return;
    }
    const el = existing ?? doc.createElement("div");
    if (existing === null) {
      el.id = DEBUGGER_INDICATOR_ID;
      // Bottom-left: the ribbon and most host chrome live on the right, and a
      // very high z-index keeps it above a modal that would otherwise hide the
      // one signal saying frames are still leaving.
      el.style.cssText =
        "position:fixed;left:8px;bottom:8px;z-index:2147483647;" +
        "padding:4px 8px;border-radius:6px;pointer-events:none;" +
        "background:#7a1f3d;color:#fff;font:600 11px/1.4 ui-monospace,monospace;" +
        "box-shadow:0 2px 8px rgba(0,0,0,.4)";
      doc.body.appendChild(el);
    }
    el.textContent = `TrUAPI wire → ${endpoints.join(", ")}`;
    el.title = "This host is streaming product wire frames to a debugger.";
  } catch {
    // A badge that cannot render must never disturb the host.
  }
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
