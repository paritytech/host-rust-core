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
import {
  resolveAccount,
  type DevAccount,
  type DevAccountName,
} from "./dev-accounts.js";

/**
 * Id the test host gives the product iframe.
 *
 * The Playwright fixture's `productFrame()` resolves against this, so the two
 * must agree; it is exported rather than duplicated as a string literal.
 */
export const PRODUCT_FRAME_ID = "product-frame";

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
  /** Accounts the host can sign as. Defaults to `["alice"]`. */
  accounts?: (DevAccountName | DevAccount)[];
  /**
   * Whether the host activates a session at boot.
   *
   * `"auto"` (the default) starts signed in, which is what most suites want.
   * `"manual"` boots with no session so a test can drive the signed-out path;
   * call `switchAccount` to sign in.
   */
  loginBehavior?: LoginBehavior;
}

/** How the test host answers login at boot. */
export type LoginBehavior = "auto" | "manual";

/**
 * Account control, which lives on the runtime rather than the platform.
 *
 * A TrUAPI host derives accounts from session entropy, so switching account
 * means re-activating the session -- it is not a host callback the mock can
 * answer, which is why these sit alongside the mock's surface rather than in
 * it.
 */
export interface AccountControl {
  /** Names the host can currently sign as, in order. */
  getAccounts(): string[];
  /** The account the current session is activated from, if any. */
  getActiveAccount(): string | undefined;
  /** Re-activate the session as `name`. */
  switchAccount(name: string): Promise<void>;
  /** Replace the roster, activating the first entry. */
  setAccounts(names: (DevAccountName | DevAccount)[]): Promise<void>;
  /** Drop the session, leaving the host signed out. */
  signOut(): Promise<void>;
}

/** What the fixture reaches on `window.__TRUAPI_TEST_HOST__`. */
export type TestHostControl = MockHost & AccountControl;

/** The running test host. */
export interface TestHostPage {
  /** The control surface the fixture reaches. */
  host: TestHostControl;
  /** The embedded product iframe. */
  iframe: HTMLIFrameElement;
  /** Tear down the iframe, the core and the channel. */
  dispose(): void;
}

declare global {
  interface Window {
    /** Published for the Playwright fixture; see the module comment. */
    __TRUAPI_TEST_HOST__?: TestHostControl;
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
    WasmSigningHostRuntime: new (
      callbacks: unknown,
      config: unknown,
    ) => WasmSigningRuntime;
  };
  await glue.default();

  const { createWasmRawCallbacks } = await import(
    "../generated/host-callbacks-adapter.js"
  );

  const host = createMockHost(options.mock);
  const { productId, ...hostConfig } = mockRuntimeConfig(
    options.runtimeConfig ?? {},
  );
  // A signing host, not a pairing host: a test host owns its keys. Note the
  // behavioural consequence -- a signing host answers `request_login` with
  // AlreadyConnected instead of starting a pairing flow, so a suite asserting
  // on pairing UI is asserting on a host role this is not.
  const runtime = new glue.WasmSigningHostRuntime(
    {
      // `workerDemandChanged` is a raw bridge callback rather than a generated
      // host callback, so it is supplied here the way the worker runtime does.
      // The test host runs one product and starts no workers, so observing the
      // transition has nothing to act on.
      ...createWasmRawCallbacks(host.callbacks),
      workerDemandChanged: () => {},
    },
    hostConfig,
  );

  let roster: DevAccount[] = (options.accounts ?? ["alice"]).map(resolveAccount);
  let active: DevAccount | undefined;

  const activate = async (account: DevAccount) => {
    if (active) await runtime.disconnectSession();
    await runtime.activateLocalSession(account.entropy);
    active = account;
  };

  if ((options.loginBehavior ?? "auto") === "auto") {
    const first = roster[0];
    if (!first) throw new Error("test host needs at least one account");
    await activate(first);
  }

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

  const control: TestHostControl = Object.assign(host, {
    getAccounts: () => roster.map((account) => account.name),
    getActiveAccount: () => active?.name,
    async switchAccount(name: string) {
      const account = roster.find((entry) => entry.name === name);
      if (!account) {
        throw new Error(
          `no account "${name}" on this host; have ${roster
            .map((entry) => entry.name)
            .join(", ")}`,
        );
      }
      await activate(account);
    },
    async setAccounts(names: (DevAccountName | DevAccount)[]) {
      roster = names.map(resolveAccount);
      const first = roster[0];
      if (!first) throw new Error("test host needs at least one account");
      await activate(first);
    },
    async signOut() {
      if (!active) return;
      await runtime.disconnectSession();
      active = undefined;
    },
  });

  // The fixture locates the product by id. `createIframeHost` does not set
  // one -- a production host has no reason to -- so the test host does.
  iframeHost.iframe.id = PRODUCT_FRAME_ID;

  window.__TRUAPI_TEST_HOST__ = control;

  return {
    host: control,
    iframe: iframeHost.iframe,
    dispose() {
      delete window.__TRUAPI_TEST_HOST__;
      core?.dispose();
      iframeHost.dispose();
      host.dispose();
    },
  };
}

/** The subset of the generated signing runtime this page drives. */
interface WasmSigningRuntime {
  activateLocalSession(secret: Uint8Array): Promise<void>;
  disconnectSession(): Promise<void>;
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
