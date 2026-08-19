import type {
  CustomRendererNode,
  HostChatActionSubscribeItem,
  WireProvider,
} from "@parity/truapi";
import { CoreStorageKey as GeneratedCoreStorageKey } from "./generated/host-callbacks.js";
import type {
  CoreAdmin,
  CoreStorageKey,
  ProductExecutionKind,
} from "./generated/host-callbacks.js";

// The typed capability interfaces below come straight from the
// `truapi-platform` Rust crate via `truapi-codegen --platform-ts-output`.
// They are the host-author-facing surface: each method takes/returns
// typed wrappers (`HostDevicePermissionRequest`, etc.) rather than raw
// SCALE bytes. The web worker pairing-host runtime adapts this typed surface
// into the byte-oriented callback bridge consumed by the WASM core.
export * from "./generated/host-callbacks.js";
export type {
  JsonRpcConnection as PlatformJsonRpcConnection,
} from "./generated/host-callbacks.js";

/** Encode a typed core-storage slot for hosts that need an opaque backing key. */
export function encodeCoreStorageKey(key: CoreStorageKey): Uint8Array {
  return GeneratedCoreStorageKey.enc(key);
}

/**
 * Async-or-sync return. Synchronous hosts (e.g. the dotli main-thread
 * shell hitting localStorage) can return a plain value; the WASM bridge
 * awaits every return so an `async` impl also works.
 */
export type Awaitable<T> = T | Promise<T>;

/**
 * Open a JSON-RPC connection for `genesisHash`. The wasm bridge passes
 * `onResponse` so the host can push JSON-RPC replies back asynchronously.
 * Returning `null` (or throwing) tells the core no provider is available.
 */
export type ChainConnect = (
  genesisHash: string,
  onResponse: (json: string) => void,
) => Awaitable<ChainConnection | null>;

/**
 * Per-connection handle returned by `chainConnect`. `send` forwards a
 * SCALE-encoded JSON-RPC request; `close` tears the connection down.
 */
export interface ChainConnection {
  send(request: string): void;
  close(): void;
}

/**
 * Verbosity threshold for the wasm core's `tracing` output. The Rust core
 * parses the string; known values are `off`, `error`, `warn`, `info`, `debug`,
 * and `trace`.
 */
export type LogLevel = string;

/** Configuration for one product runtime hosted by the wasm core. */
export interface ProductRuntimeConfig {
  /** Stable identifier used to scope product accounts, permissions, and storage. */
  productId: string;
  /** Trusted executable kind selected by the host; defaults to `App`. */
  executionKind?: ProductExecutionKind;
  /** Metadata describing the host application. */
  host: {
    /** Human-readable host name. */
    name: string;
    /** Host icon URL. */
    icon?: string;
    /** Host application version. */
    version?: string;
  };
  /** Metadata describing the platform running the host. */
  platform?: {
    /** Platform or operating-system name. */
    type?: string;
    /** Platform or operating-system version. */
    version?: string;
  };
  /** People-chain configuration used for identity lookup. */
  people: {
    /** People-chain genesis hash. */
    genesisHash: string | Uint8Array;
  };
  /** Bulletin-chain configuration used for in-core preimage submission. */
  bulletin: {
    /** Bulletin-chain genesis hash. */
    genesisHash: string | Uint8Array;
  };
  /** Wallet pairing configuration. */
  pairing: {
    /** URI scheme used for wallet pairing deeplinks. */
    deeplinkScheme: string;
  };
}

/** One stored custom Chat message the host wants the product to draw. */
export interface CustomMessageRenderRequest {
  /** Id of the stored message, as the host recorded it. */
  messageId: string;
  /** Product-defined message type, used to pick a renderer. */
  messageType: string;
  /** Opaque product-authored message body. */
  payload: Uint8Array;
}

/**
 * Sink for one custom-message render. `onUpdate` receives a complete
 * replacement tree each time; there is no patching.
 */
export interface CustomMessageRenderSink {
  onUpdate(node: CustomRendererNode): void;
  /**
   * The render ended cleanly and the last tree delivered stands. Exactly one
   * of `onComplete` or `onError` fires per render.
   */
  onComplete?(): void;
  /**
   * The render failed and any tree already delivered is partial, so it must
   * not be left on screen as final. Covers a product that declined or could
   * not encode a tree, a connection that may not reach Chat or has closed, and
   * a tree the host's own codec or renderer rejected.
   */
  onError?(error: Error): void;
}

export interface TrUApiProductProvider extends WireProvider, CoreAdmin {
  /**
   * Re-tune the wasm core's log level at runtime. Present on runtimes that
   * keep a live channel to the core (e.g. the Web Worker provider); absent on
   * one-shot constructions that only accept `logLevel` up front.
   */
  setLogLevel?(level: LogLevel): void;

  /**
   * Publish one host-authored Chat action into the product's action stream —
   * the path a tapped button in a rendered custom message takes back to the
   * product. Buffered until the product subscribes. Rejects when this
   * connection may not reach Chat.
   *
   * Present only on runtimes that keep a live channel to the core.
   */
  publishChatAction?(action: HostChatActionSubscribeItem): Promise<void>;

  /**
   * Ask the product to draw one stored custom Chat message, streaming
   * replacement trees until the returned disposer is called. Reports failure
   * through `sink.onError` rather than throwing, so a dead render never takes
   * the host's message list with it.
   *
   * Present only on runtimes that keep a live channel to the core.
   */
  renderCustomMessage?(
    request: CustomMessageRenderRequest,
    sink: CustomMessageRenderSink,
  ): () => void;
}
