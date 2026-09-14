// Browser half of the test host: the page a Playwright fixture drives.
//
// It embeds the product in an iframe, runs a real truapi-server core against
// `createMockHost`'s callbacks, and publishes the mock's control surface on
// `window.__TRUAPI_TEST_HOST__` so the fixture can reach it through
// `page.evaluate`.
//
//   Playwright (node)                    this page (browser)
//   +------------------+                 +----------------------------------+
//   | fixture          |  page.evaluate  | window.__TRUAPI_TEST_HOST__      |
//   | testHost.*       |---------------->| createMockHost() control surface |
//   +------------------+                 +----------------------------------+
//                                             ^ callbacks
//                                        +----------------------------------+
//                                        | truapi-server WASM core          |
//                                        +----------------------------------+
//                                             ^ SCALE frames over MessagePort
//                                        +----------------------------------+
//                                        | product iframe (#product-frame)  |
//                                        +----------------------------------+
//
// The core runs on the page's main thread rather than in a Worker: a test host
// has no UI to keep responsive, and one less moving part is one less thing to
// debug when a suite fails.

import { createIframeHost } from "../web/create-iframe-host.js";
import {
  createMockHost,
  mockRuntimeConfig,
  type MockHost,
  type MockHostConfig,
} from "../web/create-mock-host.js";
import type { ProductRuntimeConfig } from "../runtime.js";

/** Options for {@link startTestHost}. */
export interface TestHostPageOptions {
  /** URL of the product under test. */
  productUrl: string;
  /** Element the product iframe is appended to. */
  container: HTMLElement;
  /** Behaviour knobs forwarded to {@link createMockHost}. */
  mock?: MockHostConfig;
  /** Overrides merged into {@link mockRuntimeConfig}. */
  runtimeConfig?: Partial<ProductRuntimeConfig>;
  /**
   * Resolved WASM entry. Defaults to the signing-enabled `testing` bundle,
   * which is what lets the host own dev accounts instead of waiting on a
   * wallet that is not there.
   */
  wasmUrl?: string;
}

/** The running test host. */
export interface TestHostPage {
  /** The mock's control surface, the same object the fixture reaches. */
  host: MockHost;
  /** The embedded product iframe. */
  iframe: HTMLIFrameElement;
  /** Tear down the iframe, the core and the channel. */
  dispose(): void;
}

declare global {
  interface Window {
    /** Published for the Playwright fixture; see the module comment. */
    __TRUAPI_TEST_HOST__?: MockHost;
  }
}

/**
 * Boot the test host into `container` and publish its control surface.
 *
 * Resolves once the core is running and the product iframe has its port, so a
 * fixture that awaits this can assume the wire is live.
 */
export async function startTestHost(
  options: TestHostPageOptions,
): Promise<TestHostPage> {
  const wasmUrl = options.wasmUrl ?? "./wasm/testing/truapi_server.js";
  const glue = (await import(/* @vite-ignore */ wasmUrl)) as {
    default: () => Promise<unknown>;
    WasmPairingHostRuntime: new (
      callbacks: unknown,
      config: unknown,
    ) => WasmRuntime;
  };
  await glue.default();

  const { createWasmRawCallbacks } = await import(
    "../generated/host-callbacks-adapter.js"
  );

  const host = createMockHost(options.mock);
  const { productId, ...hostConfig } = mockRuntimeConfig(
    options.runtimeConfig ?? {},
  );
  const runtime = new glue.WasmPairingHostRuntime(
    createWasmRawCallbacks(host.callbacks),
    hostConfig,
  );

  // The core and the product each hold one end of a MessageChannel. Frames
  // are raw SCALE bytes in both directions; nothing interprets them here.
  let core: ProductCore | undefined;
  const iframeHost = createIframeHost({
    iframeUrl: options.productUrl,
    container: options.container,
    onPort(port) {
      core = runtime.productRuntime(
        { productId },
        {
          emitFrame(frame: Uint8Array) {
            port.postMessage(frame);
          },
        },
      );
      port.onmessage = (event: MessageEvent) => {
        const frame = event.data;
        if (frame instanceof Uint8Array) void core?.receiveFrame(frame);
      };
      port.start();
    },
  });

  window.__TRUAPI_TEST_HOST__ = host;

  return {
    host,
    iframe: iframeHost.iframe,
    dispose() {
      delete window.__TRUAPI_TEST_HOST__;
      core?.dispose();
      iframeHost.dispose();
      host.dispose();
    },
  };
}

/** The subset of the generated WASM runtime this page drives. */
interface WasmRuntime {
  productRuntime(
    product: { productId: string },
    sink: { emitFrame(frame: Uint8Array): void },
  ): ProductCore;
}

/** The subset of a per-product core this page drives. */
interface ProductCore {
  receiveFrame(frame: Uint8Array): Promise<void>;
  dispose(): void;
}
