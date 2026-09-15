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
import { createTestHostServer } from "./server.js";
import type { TestHostServer } from "./server.js";

// Re-exported so a migrating test file imports from one path, the way
// `@parity/host-api-test-sdk/playwright` does.
export {
  DEFAULT_CHAIN,
  DEV_ACCOUNTS,
  LIVE_CHAINS,
  PASEO_ASSET_HUB,
  liveChain,
} from "./dev-accounts.js";
export type { DevAccount, DevAccountName } from "./dev-accounts.js";

/** Selector for the product iframe the host page creates. */
const PRODUCT_FRAME = `#${PRODUCT_FRAME_ID}`;

/** Options for {@link createTestHostFixture}. */
export interface TestHostFixtureOptions {
  /** URL of the product under test. */
  productUrl: string;
  /**
   * Base URL of a running host page server.
   *
   * Optional. Omit it and the fixture starts one itself, lazily, and shares it
   * across every test in the file -- bundling is not cached, so one server per
   * test would pay esbuild each time. Supply it to control the lifetime.
   */
  hostUrl?: string;
  /**
   * Chains to serve, in `@parity/host-api-test-sdk`'s `NetworkConfig` shape.
   *
   * A convenience over spelling out `mock.chainProxies`, `mock.supportedChains`
   * and `runtimeConfig` separately, which have to agree. The chain's role is
   * read from the `id` suffix (`-asset-hub`, `-people`, `-bulletin`, else the
   * relay) and the rest of the id is the network name.
   *
   * Explicit `mock` or `runtimeConfig` values win, so a suite can start here
   * and override one piece.
   */
  networks?: NetworkConfig[];
  /**
   * Accepted only to fail with an explanation. See the error text: TrUAPI
   * derives a product account from the session root, so it cannot be pinned.
   */
  productAccounts?: Record<string, string>;
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
  /**
   * Accounts the host can sign as. Defaults to `["alice"]`.
   *
   * Objects are accepted for `@parity/host-api-test-sdk` compatibility, but a
   * `uri` is rejected: a TrUAPI session activates from 32 bytes of entropy,
   * not a `//Alice`-style derivation path.
   */
  accounts?: (string | { name: string; uri?: string })[];
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

  /**
   * Release the host.
   *
   * A no-op. Playwright owns the page's lifetime and closes it when the test
   * ends, so a suite has nothing to release. Present so a migrating suite does
   * not have to strip a teardown call that is simply unnecessary here.
   */
  dispose(): Promise<void>;

  /** Set the spendable balance. Always throws; payments are unimplemented. */
  setPaymentBalance(amount: bigint): Promise<never>;
  /** Payment operations the product performed. Always throws; see above. */
  getPaymentLog(): Promise<never>;
  /** Drop the payment log. Always throws; see above. */
  clearPaymentLog(): Promise<never>;
  /** How top-ups resolve. Always throws; see above. */
  setPaymentTopUpBehavior(behavior: unknown): Promise<never>;
  /** Force a payment's status. Always throws; see above. */
  simulatePaymentStatus(
    paymentId: string,
    status: { tag: string; value?: string },
  ): Promise<never>;

  /**
   * Deliver a peer's activation of a chat action to the product.
   *
   * Always throws. `ChatPlatform` is create/register/post/subscribe-rooms only,
   * so a peer activating an action has no way into the core. `ChatAction`
   * exists as message *content* a product posts, not as an inbound event.
   */
  injectChatAction(action: {
    roomId: string;
    peer: string;
    payload: unknown;
  }): Promise<never>;

  /**
   * Change the login behaviour after boot.
   *
   * Always throws, and says what to do instead: the host page reads it once at
   * start, so it is a `loginBehavior` option on `createTestHostFixture`.
   */
  setLoginBehavior(behavior: "auto" | "manual"): Promise<never>;
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
 * Why the payment controls cannot be served.
 *
 * Not a seam the mock declined to implement: every method in the core's
 * `capabilities/payment.rs` returns an error and ignores its arguments, so
 * there is no behaviour for a host to model or a test to observe.
 */
const NO_PAYMENT_SEAM =
  "is not available in the TrUAPI test host: the protocol declares payments " +
  "but no host implements them -- every method in the core's payment " +
  "capability returns an error and ignores its arguments, so there is nothing " +
  "to record or simulate. See docs/rfcs/0006-payments.md.";

/** Why a chat action cannot be injected. */
const NO_CHAT_ACTION_SEAM =
  "is not available in the TrUAPI test host: `ChatPlatform` is create-room, " +
  "register-bot, post-message and subscribe-rooms only, so a peer activating " +
  "an action has no way into the core. Actions exist as message content a " +
  "product posts, not as an inbound event. The calls the core makes ARE " +
  "recorded -- see getChatRooms, getChatBots and getChatMessageLog.";

/** Why login behaviour is fixed once the host page has booted. */
const LOGIN_BEHAVIOR_IS_CONSTRUCTION_TIME =
  "cannot be changed after boot in the TrUAPI test host: the host page reads " +
  "it once at start. Pass `loginBehavior: \"auto\" | \"manual\"` to " +
  "createTestHostFixture instead.";

/** One chain, in `@parity/host-api-test-sdk`'s shape. */
export interface NetworkConfig {
  /** e.g. `paseo-asset-hub`; the suffix names the chain's role. */
  id: string;
  name?: string;
  genesisHash: string;
  rpcUrl: string;
  tokenSymbol?: string;
  tokenDecimals?: number;
}

/** Why a product account cannot be pinned to a chosen key. */
const NO_PINNED_PRODUCT_ACCOUNT =
  "is not supported by the TrUAPI test host: a product account is DERIVED " +
  "from (session root, product id), so it cannot be mapped to a chosen dev " +
  "account. `@parity/host-api-test-sdk` could pin one because it reimplements " +
  "the protocol with no core behind it. Read the address back from the host " +
  "instead of pinning it, and expect switching the host account to change the " +
  "product account -- that is the real behaviour, not a test-host limitation.";

/** Why a derivation URI cannot name an account. */
const NO_DERIVATION_URI =
  "is not supported by the TrUAPI test host: a session activates from 32 " +
  "bytes of BIP-39 entropy, not a `//Alice`-style derivation path, so the " +
  "addresses differ from polkadot-js's by construction. Use a built-in name " +
  "(alice, bob, charlie, dave) or pass explicit entropy.";

/** Role and network implied by a `NetworkConfig.id`. */
function splitChainId(id: string): {
  network: string;
  identifier: "AssetHub" | "People" | "Bulletin" | "Relay";
  configKey?: "assetHub" | "people" | "bulletin";
} {
  const suffixes = [
    ["-asset-hub", "AssetHub", "assetHub"],
    ["-people", "People", "people"],
    ["-bulletin", "Bulletin", "bulletin"],
  ] as const;
  for (const [suffix, identifier, configKey] of suffixes) {
    if (id.endsWith(suffix)) {
      return { network: id.slice(0, -suffix.length), identifier, configKey };
    }
  }
  // No suffix: the id names the network and the chain is its relay. The
  // runtime config has no relay slot, so there is no key to declare it under.
  return { network: id, identifier: "Relay" };
}

/**
 * Expand `networks` into the three settings that have to agree.
 *
 * The proxy entries carry no genesis hash: an unhashed proxy takes every
 * request, so routing survives a chain reset while only the DECLARED hash --
 * which the product checks against its descriptor bundle -- needs re-pinning.
 */
export function fromNetworks(networks: NetworkConfig[]): {
  mock: Pick<MockHostConfig, "chainProxies" | "supportedChains">;
  runtimeConfig: Record<string, unknown>;
} {
  const runtimeConfig: Record<string, unknown> = {};
  const chains: { identifier: string; genesisHash: string }[] = [];
  let network = "paseo";
  for (const entry of networks) {
    const split = splitChainId(entry.id);
    network = split.network || network;
    chains.push({
      identifier: split.identifier,
      genesisHash: entry.genesisHash,
    });
    if (split.configKey) {
      runtimeConfig[split.configKey] = { genesisHash: entry.genesisHash };
    }
  }
  return {
    mock: {
      chainProxies: networks.map((entry) => ({ rpcUrl: entry.rpcUrl })),
      supportedChains: { network, chains },
    } as Pick<MockHostConfig, "chainProxies" | "supportedChains">,
    runtimeConfig,
  };
}

/** Account names for the page URL, rejecting anything the host cannot honour. */
function accountNames(
  accounts: (string | { name: string; uri?: string })[],
): string[] {
  return accounts.map((account) => {
    if (typeof account === "string") return account;
    if (account.uri !== undefined) {
      throw new Error(
        `testHost account "${account.name}": \`uri\` ${NO_DERIVATION_URI}`,
      );
    }
    return account.name;
  });
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
  if (defaults.productAccounts) {
    throw new Error(`testHost \`productAccounts\` ${NO_PINNED_PRODUCT_ACCOUNT}`);
  }
  // Started at most once and shared by every test in the file. Held as the
  // promise, not the server, so concurrent first tests await one start rather
  // than racing two.
  // Validated here rather than in the fixture body: a bad option should fail
  // when the suite is constructed, not inside the first test that runs.
  const accounts = defaults.accounts
    ? accountNames(defaults.accounts)
    : undefined;
  let ownServer: Promise<TestHostServer> | undefined;
  const hostBase = async (): Promise<string> => {
    if (defaults.hostUrl) return defaults.hostUrl;
    ownServer ??= createTestHostServer({ unref: true });
    return (await ownServer).url;
  };

  const expanded = defaults.networks ? fromNetworks(defaults.networks) : undefined;
  // Explicit settings win over anything derived from `networks`.
  const mock = expanded ? { ...expanded.mock, ...defaults.mock } : defaults.mock;
  const runtimeConfig = expanded
    ? { ...expanded.runtimeConfig, ...defaults.runtimeConfig }
    : defaults.runtimeConfig;

  return {
    testHost: async (
      { page }: { page: Page },
      use: (fixture: TestHost) => Promise<void>,
    ) => {
      const url = new URL(await hostBase());
      url.searchParams.set("product", defaults.productUrl);
      if (mock) {
        url.searchParams.set("mock", JSON.stringify(mock));
      }
      if (defaults.productId) {
        url.searchParams.set("productId", defaults.productId);
      }
      if (runtimeConfig) {
        url.searchParams.set("runtimeConfig", JSON.stringify(runtimeConfig));
      }
      if (accounts) {
        url.searchParams.set("accounts", accounts.join(","));
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

        // Playwright closes the page after the fixture yields, so there is
        // genuinely nothing to do -- not a silent stub standing in for work.
        dispose: () => Promise.resolve(),

        setPaymentBalance: () => {
          throw new Error(`testHost.setPaymentBalance ${NO_PAYMENT_SEAM}`);
        },
        getPaymentLog: () => {
          throw new Error(`testHost.getPaymentLog ${NO_PAYMENT_SEAM}`);
        },
        clearPaymentLog: () => {
          throw new Error(`testHost.clearPaymentLog ${NO_PAYMENT_SEAM}`);
        },
        setPaymentTopUpBehavior: () => {
          throw new Error(`testHost.setPaymentTopUpBehavior ${NO_PAYMENT_SEAM}`);
        },
        simulatePaymentStatus: () => {
          throw new Error(`testHost.simulatePaymentStatus ${NO_PAYMENT_SEAM}`);
        },
        injectChatAction: () => {
          throw new Error(`testHost.injectChatAction ${NO_CHAT_ACTION_SEAM}`);
        },
        setLoginBehavior: () => {
          throw new Error(
            `testHost.setLoginBehavior ${LOGIN_BEHAVIOR_IS_CONSTRUCTION_TIME}`,
          );
        },
      };

      await use(testHost);
    },
  };
}
