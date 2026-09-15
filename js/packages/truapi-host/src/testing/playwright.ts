// Playwright fixture over the test host.
//
// The node half of the pair described in `host-page.ts`: every method here is
// a `page.evaluate` against `window.__TRUAPI_TEST_HOST__`, so the control
// surface a test drives is the same object the core is answering through.
//
// The method names match `@parity/host-api-test-sdk`'s `TestHost` so a suite
// migrating onto this changes its import, not its assertions. Where a name is
// absent it is because TrUAPI has no seam for it -- see `notModeled` in
// `create-mock-host.ts`; those throw rather than silently pass.

import type { Page, FrameLocator } from "@playwright/test";

import type {
  ChainStatus,
  ChatMessageRecord,
  MockHostConfig,
  PermissionDecision,
  PermissionPolicy,
  SigningLogEntry,
} from "../web/create-mock-host.js";

import { PRODUCT_FRAME_ID } from "./host-page.js";

/** Selector for the product iframe the host page creates. */
const PRODUCT_FRAME = `#${PRODUCT_FRAME_ID}`;

/** Options for {@link createTestHostFixture}. */
export interface TestHostFixtureOptions {
  /** URL of the product under test. */
  productUrl: string;
  /**
   * Base URL of a running host page server.
   *
   * The server is supplied rather than started here so a suite can share one
   * across tests instead of paying page-load and WASM-init per case.
   */
  hostUrl: string;
  /**
   * dotNS identifier the host runs the product under.
   *
   * Must match the identifier the product signs with: the core rejects a
   * signing request whose account is scoped to a different product, so a
   * mismatch surfaces as `PermissionDenied` rather than as a config error.
   */
  productId?: string;
  /** Behaviour knobs forwarded to the mock host, including `chainProxies`. */
  mock?: MockHostConfig;
  /**
   * Overrides merged into the host's runtime config.
   *
   * Proxying a real chain needs this: the core asks for a chain by the genesis
   * hash the config declares, so that hash has to be the real one rather than
   * a {@link MOCK_GENESIS} placeholder.
   */
  runtimeConfig?: Record<string, unknown>;
  /** Accounts the host can sign as. Defaults to `["alice"]`. */
  accounts?: string[];
  /** Whether the host starts signed in. Defaults to `"auto"`. */
  loginBehavior?: "auto" | "manual";
  /** How long to wait for the host page to publish its control surface. */
  readyTimeoutMs?: number;
}

/** The fixture a test receives. */
export interface TestHost {
  /** The Playwright page running the host. */
  page: Page;
  /** Locator for the embedded product. */
  productFrame(): FrameLocator;

  getNavigationLog(): Promise<string[]>;
  clearNavigationLog(): Promise<void>;
  getNotificationLog(): Promise<unknown[]>;
  clearNotificationLog(): Promise<void>;
  getSigningLog(): Promise<SigningLogEntry[]>;
  clearSigningLog(): Promise<void>;
  getPermissionLog(): Promise<PermissionDecision[]>;
  clearPermissionLog(): Promise<void>;
  getGrantedPermissions(): Promise<string[]>;
  grantPermission(permission: string): Promise<void>;
  revokePermission(permission: string): Promise<void>;
  setEnforcePermissions(enforce: boolean): Promise<void>;
  setPermissionBehavior(behavior: PermissionPolicy): Promise<void>;
  getChatRooms(): Promise<unknown[]>;
  getChatBots(): Promise<unknown[]>;
  getChatMessageLog(): Promise<ChatMessageRecord[]>;
  clearChatState(): Promise<void>;
  /** Product-scoped storage the core has written, keyed without the prefix. */
  getProductStorage(): Promise<Record<string, Uint8Array>>;
  getPreimages(): Promise<Uint8Array[]>;
  seedPreimage(value: Uint8Array): Promise<Uint8Array>;
  /**
   * Find the value the product stored under `key`.
   *
   * The core namespaces product storage keys before the host ever sees them,
   * so a test matching on the product's own key wants a suffix match rather
   * than the full namespaced string, which is an internal shape.
   */
  findProductStorage(key: string): Promise<Uint8Array | undefined>;
  clearPreimages(): Promise<void>;
  getTheme(): Promise<string>;
  setTheme(variant: string): Promise<void>;
  getIsAuthenticated(): Promise<boolean>;
  getChainStatus(): Promise<ChainStatus>;
  getConnectionStatus(): Promise<ChainStatus>;
  /**
   * Raw JSON-RPC the core sent over the chain connection, in order.
   *
   * A chain-path failure is otherwise invisible from a suite: the product
   * shows a stalled UI and the fixture reports nothing about what the host
   * asked the chain. This is what tells you whether a request was made at
   * all, and what came back after it.
   */
  getSentRpc(): Promise<string[]>;
  /** Drop the recorded RPC, so one case does not read another's traffic. */
  clearSentRpc(): Promise<void>;
  simulateDisconnect(): Promise<void>;
  simulateReconnect(): Promise<void>;
  /**
   * Wait until the product has an open channel to the host.
   *
   * Resolves once the core has answered at least one product call, which is
   * the first observable evidence that frames are crossing the wire in both
   * directions.
   */
  waitForConnection(timeoutMs?: number): Promise<void>;
  /** Names the host can currently sign as. */
  getAccounts(): Promise<string[]>;
  /** The account the current session is activated from, if any. */
  getActiveAccount(): Promise<string | undefined>;
  /** Re-activate the session as `name`. */
  switchAccount(name: string): Promise<void>;
  /** Replace the roster, activating the first entry. */
  setAccounts(names: string[]): Promise<void>;
  /** Drop the session, leaving the host signed out. */
  signOut(): Promise<void>;
  /** Return the host to its constructed state between cases. */
  reset(): Promise<void>;

  /**
   * Statements the product submitted.
   *
   * Always throws. The statement store is core-owned and submission is
   * rejected inside the core before any RPC is emitted, so there is nothing
   * for the host to record -- not a host seam the mock declined to implement.
   */
  getSubmittedStatements(): Promise<never>;
  /** Deliver a statement to the product. Always throws; see above. */
  injectStatement(statement: unknown): Promise<never>;
  /** Drop the recorded statements. Always throws; see above. */
  clearStatements(): Promise<never>;
}

/**
 * Why the statement-store controls cannot be served.
 *
 * Stated once so every one of them says the same thing, and says which half is
 * missing: the transport works -- a proxied people chain connects and
 * `statement_subscribeStatement` is visible in `getSentRpc` -- but submission
 * never reaches it.
 */
const NO_STATEMENT_SEAM =
  "is not available in the TrUAPI test host: the statement store is owned by " +
  "the core, not the host, so there is no seam to record or inject through. " +
  "Submission is rejected inside the core before any RPC is emitted (it needs " +
  "a statement allowance), so it cannot be observed on the chain transport " +
  "either. Subscription traffic IS visible via the proxied chain.";

/**
 * Build the `testHost` fixture.
 *
 * ```ts
 * export const test = base.extend(createTestHostFixture({
 *   productUrl: "http://127.0.0.1:5173",
 *   hostUrl: server.url,
 * }));
 * ```
 */
export function createTestHostFixture(defaults: TestHostFixtureOptions) {
  return {
    testHost: async (
      { page }: { page: Page },
      use: (fixture: TestHost) => Promise<void>,
    ) => {
      const url = new URL(defaults.hostUrl);
      url.searchParams.set("product", defaults.productUrl);
      if (defaults.mock) {
        url.searchParams.set("mock", JSON.stringify(defaults.mock));
      }
      if (defaults.productId) {
        url.searchParams.set("productId", defaults.productId);
      }
      if (defaults.runtimeConfig) {
        url.searchParams.set(
          "runtimeConfig",
          JSON.stringify(defaults.runtimeConfig),
        );
      }
      if (defaults.accounts) {
        url.searchParams.set("accounts", defaults.accounts.join(","));
      }
      if (defaults.loginBehavior) {
        url.searchParams.set("login", defaults.loginBehavior);
      }
      await page.goto(url.toString());

      // The page publishes its control surface only once the WASM core is up
      // and the product has its port, so this doubles as the wire's ready gate.
      await page.waitForFunction(() => !!window.__TRUAPI_TEST_HOST__, {
        timeout: defaults.readyTimeoutMs ?? 30_000,
      });

      /** Call one control method in the page and return its result. */
      const call = <T>(method: string, ...args: unknown[]): Promise<T> =>
        page.evaluate(
          ([name, callArgs]: [string, unknown[]]) => {
            const host = window.__TRUAPI_TEST_HOST__;
            if (!host) throw new Error("test host is not running on this page");
            const fn = (host as unknown as Record<string, unknown>)[name];
            if (typeof fn !== "function") {
              throw new Error(`test host has no control method ${name}`);
            }
            return (fn as (...a: unknown[]) => unknown).apply(host, callArgs);
          },
          [method, args] as [string, unknown[]],
        ) as Promise<T>;

      const testHost: TestHost = {
        page,
        productFrame: () => page.frameLocator(PRODUCT_FRAME),

        getNavigationLog: () => call("getNavigationLog"),
        clearNavigationLog: () => call("clearNavigationLog"),
        getNotificationLog: () => call("getNotificationLog"),
        clearNotificationLog: () => call("clearNotificationLog"),
        getSigningLog: () => call("getSigningLog"),
        clearSigningLog: () => call("clearSigningLog"),
        getPermissionLog: () => call("getPermissionLog"),
        clearPermissionLog: () => call("clearPermissionLog"),
        getGrantedPermissions: () => call("getGrantedPermissions"),
        grantPermission: (permission) => call("grantPermission", permission),
        revokePermission: (permission) => call("revokePermission", permission),
        setEnforcePermissions: (enforce) =>
          call("setEnforcePermissions", enforce),
        setPermissionBehavior: (behavior) =>
          call("setPermissionBehavior", behavior),
        getChatRooms: () => call("getChatRooms"),
        getChatBots: () => call("getChatBots"),
        getChatMessageLog: () => call("getChatMessageLog"),
        clearChatState: () => call("clearChatState"),
        // `page.evaluate` serialises a Uint8Array as a plain index object, so
        // binary values are converted to arrays in the page and rebuilt here.
        // Without this a caller gets `{0: 114, …}` and any decode of it
        // silently yields "".
        getProductStorage: async () => {
          const raw = await page.evaluate(() => {
            const host = window.__TRUAPI_TEST_HOST__;
            if (!host) throw new Error("test host is not running on this page");
            return Object.fromEntries(
              Object.entries(host.getProductStorage()).map(([key, value]) => [
                key,
                Array.from(value),
              ]),
            );
          });
          return Object.fromEntries(
            Object.entries(raw).map(([key, value]) => [
              key,
              Uint8Array.from(value),
            ]),
          );
        },
        async findProductStorage(key: string) {
          const stored = await testHost.getProductStorage();
          const match = Object.entries(stored).find(([stored]) =>
            stored.endsWith(`:${key}`),
          );
          return match?.[1];
        },
        getPreimages: async () => {
          const raw = await page.evaluate(() => {
            const host = window.__TRUAPI_TEST_HOST__;
            if (!host) throw new Error("test host is not running on this page");
            return host.getPreimages().map((value) => Array.from(value));
          });
          return raw.map((value) => Uint8Array.from(value));
        },
        seedPreimage: (value) => call("seedPreimage", value),
        clearPreimages: () => call("clearPreimages"),
        getTheme: () => call("getTheme"),
        setTheme: (variant) => call("setTheme", variant),
        getIsAuthenticated: () => call("getIsAuthenticated"),
        getChainStatus: () => call("getChainStatus"),
        getConnectionStatus: () => call("getConnectionStatus"),
        getSentRpc: () => call("sentRpc"),
        clearSentRpc: () => call("clearSentRpc"),
        simulateDisconnect: () => call("simulateDisconnect"),
        simulateReconnect: () => call("simulateReconnect"),
        async waitForConnection(timeoutMs = 30_000) {
          // A live wire means the core has actually called the host, not
          // merely that the page finished loading.
          await page.waitForFunction(
            () => (window.__TRUAPI_TEST_HOST__?.getHostCallCount() ?? 0) > 0,
            { timeout: timeoutMs },
          );
        },
        getAccounts: () => call("getAccounts"),
        getActiveAccount: () => call("getActiveAccount"),
        // Switching account re-activates the session, which reloads the
        // product iframe; wait for it so the next action does not race it.
        switchAccount: async (name) => {
          await call("switchAccount", name);
          await page
            .frameLocator(PRODUCT_FRAME)
            .locator("body")
            .waitFor({ state: "attached" });
        },
        setAccounts: async (names) => {
          await call("setAccounts", names);
          await page
            .frameLocator(PRODUCT_FRAME)
            .locator("body")
            .waitFor({ state: "attached" });
        },
        signOut: () => call("signOut"),
        reset: () => call("reset"),

        getSubmittedStatements: () => {
          throw new Error(`testHost.getSubmittedStatements ${NO_STATEMENT_SEAM}`);
        },
        injectStatement: () => {
          throw new Error(`testHost.injectStatement ${NO_STATEMENT_SEAM}`);
        },
        clearStatements: () => {
          throw new Error(`testHost.clearStatements ${NO_STATEMENT_SEAM}`);
        },
      };

      await use(testHost);
    },
  };
}
