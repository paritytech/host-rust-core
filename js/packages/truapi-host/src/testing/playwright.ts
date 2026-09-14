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

/** Id of the product iframe the host page creates. */
const PRODUCT_FRAME = "#product-frame";

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
  /** Behaviour knobs forwarded to the mock host. */
  mock?: MockHostConfig;
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
  getPreimages(): Promise<Uint8Array[]>;
  seedPreimage(value: Uint8Array): Promise<Uint8Array>;
  clearPreimages(): Promise<void>;
  getTheme(): Promise<string>;
  setTheme(variant: string): Promise<void>;
  getIsAuthenticated(): Promise<boolean>;
  getChainStatus(): Promise<ChainStatus>;
  getConnectionStatus(): Promise<ChainStatus>;
  simulateDisconnect(): Promise<void>;
  simulateReconnect(): Promise<void>;
  /** Return the host to its constructed state between cases. */
  reset(): Promise<void>;
}

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
        getPreimages: () => call("getPreimages"),
        seedPreimage: (value) => call("seedPreimage", value),
        clearPreimages: () => call("clearPreimages"),
        getTheme: () => call("getTheme"),
        setTheme: (variant) => call("setTheme", variant),
        getIsAuthenticated: () => call("getIsAuthenticated"),
        getChainStatus: () => call("getChainStatus"),
        getConnectionStatus: () => call("getConnectionStatus"),
        simulateDisconnect: () => call("simulateDisconnect"),
        simulateReconnect: () => call("simulateReconnect"),
        reset: () => call("reset"),
      };

      await use(testHost);
    },
  };
}
