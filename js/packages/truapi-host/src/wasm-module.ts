// Shape of the web-targeted truapi-server WASM bundle. `make wasm` writes the
// wasm-pack glue and its `.wasm` payload to `dist/wasm/web/`; the ambient
// declaration in `src/wasm/web/truapi_server.d.ts` types that module against
// these interfaces so the worker can name it in a statically analysable import.

import type { PermissionAuthorizationRuntime } from "./worker-permission-authorization.js";

export interface WorkerCustomRendererSubscription {
  cancel(): void;
  free(): void;
}

/** One product-scoped core inside the worker. */
export interface WorkerProductRuntime {
  receiveFrame(frame: Uint8Array): Promise<void>;
  dispose(): void;
  free(): void;
  /** Throws when the connection may not reach Chat. */
  publishChatAction(action: Uint8Array): void;
  /**
   * Start the host-initiated render subscription for one stored custom Chat
   * message. `onUpdate` receives each SCALE-encoded `CustomRendererNode`, then
   * exactly one of `onComplete` (last tree stands) or `onError` (the product
   * could not serve the render; the last tree is partial).
   */
  renderCustomMessage(
    messageId: string,
    messageType: string,
    payload: Uint8Array,
    onUpdate: (node: Uint8Array) => void,
    onComplete: () => void,
    onError: (reason: string) => void,
  ): WorkerCustomRendererSubscription;
}

/** The long-lived pairing-host runtime product cores are created from. */
export interface WorkerPairingHostRuntime extends PermissionAuthorizationRuntime {
  productRuntime(
    product: unknown,
    coreCallbacks: unknown,
  ): WorkerProductRuntime;
  disconnectSession(): Promise<void>;
  cancelPairing(): void;
  notifySessionStoreChanged(): void;
  sessionChatIdentityKey(): Uint8Array | undefined;
  deviceEncryptionKey(): Promise<Uint8Array>;
  activateStoredSession(): Promise<void>;
  activateExternalSession(blob: Uint8Array): Promise<void>;
  resetSessionState(): Promise<void>;
  free(): void;
}

/** Module surface the wasm-pack glue exports. */
export interface WasmModuleShape {
  default: (input?: unknown) => Promise<unknown>;
  WasmPairingHostRuntime: new (
    callbacks: unknown,
    hostConfig: unknown,
  ) => WorkerPairingHostRuntime;
  WasmProductRuntime: new (
    callbacks: unknown,
    runtimeConfig: unknown,
  ) => WorkerProductRuntime;
  setLogLevel?: (level: string) => void;
}
