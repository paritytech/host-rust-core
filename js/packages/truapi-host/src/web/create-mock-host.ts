// A deterministic, in-memory mock host. `createMockHost` returns a complete
// `RequiredHostCallbacks` set (the JS sibling of `truapi-platform`'s
// `MockPlatform`) plus recordings for assertions. Hand `host.callbacks` to
// `createWebWorkerPairingHostRuntime` (or `createWasmRawCallbacks` directly) to
// run the real truapi-server WASM core against a mocked OS seam: storage is
// in-memory, permissions answer from a fixed policy, navigation/notifications
// are recorded, and the chain connection is silent (or replays canned frames).
//
// Signing and login park here because this mock backs a *pairing* host, which
// holds no key material of its own: both wait on a paired wallet answering
// over the statement-store channel, and the default silent chain never
// answers. The limit is the host role rather than the mock or the chain — a
// signing host's `sign_raw` completes against this same silent chain.
// Everything else (storage, permissions, features, theme, navigation,
// notifications, preimage lookup) works without a wallet.
//
// Preimage submission is core-owned on current core (the core builds, signs,
// and submits the Bulletin `TransactionStorage.store` transaction itself), so
// the mock only implements host-side content retrieval via `lookupPreimage`;
// seed retrievable content with the returned `insertPreimage`.

import { ok } from "neverthrow";

import type {
  GenericError,
  HostLocaleSubscribeItem,
  HostPushNotificationRequest,
  HostThemeSubscribeItem,
  Result,
  ThemeVariant,
} from "@parity/truapi";

import type {
  AuthState,
  CoreStorageKey,
  HostChainSet,
  JsonRpcConnection,
  RequiredHostCallbacks,
} from "../generated/host-callbacks.js";
import type { ProductRuntimeConfig } from "../runtime.js";

/** How the mock answers a permission prompt for one capability. */
export type PermissionPolicy = "allow-all" | "deny-all";

/** Behavior knobs for {@link createMockHost}. */
export interface MockHostConfig {
  /** Answer for `devicePermission`. Default `"allow-all"`. */
  devicePermissions?: PermissionPolicy;
  /** Answer for `remotePermission`. Default `"allow-all"`. */
  remotePermissions?: PermissionPolicy;
  /** Whether `featureSupported` reports support. Default `true`. */
  featureSupported?: boolean;
  /** Theme emitted by `subscribeTheme`. Default `"Dark"`. */
  theme?: ThemeVariant;
  /** BCP 47 tag emitted by `subscribeLocale`. Default `"en"`. */
  languageTag?: string;
  /** Whether `confirmUserAction` confirms reviewed actions. Default `true`. */
  confirmUserActions?: boolean;
  /**
   * JSON-RPC response frames the chain connection replays, in order. Empty
   * (the default) means a silent connection: it records outbound requests and
   * never answers, so chain-dependent flows park.
   */
  chainResponses?: string[];
  /**
   * When `true`, the chain response stream ends immediately instead of parking,
   * so disconnect/timeout paths can be asserted (fail-fast). Ignored when
   * `chainResponses` is non-empty.
   */
  chainClosed?: boolean;
  /**
   * Chains the host reports serving (RFC 0026). Defaults to the three
   * {@link MOCK_GENESIS} chains, which are what {@link mockRuntimeConfig}
   * declares.
   *
   * An empty set type-checks and then fails every chain-routed call, so
   * override this only to assert that failure.
   */
  supportedChains?: HostChainSet;
}

/** A mock host: the callbacks to wire into a provider, plus assertion oracles. */
export interface MockHost {
  /**
   * The nested host-callback surface. Pass to `createWasmRawCallbacks` or hand
   * to `createWebWorkerPairingHostRuntime` (both accept `RequiredHostCallbacks`).
   */
  callbacks: RequiredHostCallbacks;
  /** URLs the core asked the host to open, in order. */
  navigations(): string[];
  /** Notifications the core asked the host to show, in order. */
  pushedNotifications(): HostPushNotificationRequest[];
  /** Raw JSON-RPC the core sent over the chain connection, in order. */
  sentRpc(): string[];
  /** Auth-state transitions the core emitted, in order. */
  authStates(): AuthState[];
  /** Confirmation kinds the core requested (review `tag`s), in order. */
  confirmations(): string[];
  /** Notification ids the core asked the host to cancel, in order. */
  cancelledNotifications(): number[];
  /**
   * Seed a preimage so a later `preimage.lookupPreimage` resolves it, and
   * return the deterministic lookup key. The core (not the host) owns Bulletin
   * submission on current core; this is the host-side content store the mock's
   * `lookupPreimage` reads from.
   */
  insertPreimage(value: Uint8Array): Uint8Array;
}

/** Deterministic 8-byte key for a preimage value (FNV-1a), so `insertPreimage`
 *  then `lookupPreimage` round-trips without using the full value as its key. */
function preimageKey(value: Uint8Array): Uint8Array {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const mask = 0xffffffffffffffffn;
  for (const byte of value) {
    hash = ((hash ^ BigInt(byte)) * prime) & mask;
  }
  const key = new Uint8Array(8);
  for (let i = 0; i < 8; i++) {
    key[i] = Number((hash >> BigInt(8 * i)) & 0xffn);
  }
  return key;
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Build an in-memory mock host. The returned `callbacks` implement every
 * `RequiredHostCallbacks` capability; the accessor methods expose what the core
 * did.
 */
export function createMockHost(config: MockHostConfig = {}): MockHost {
  const {
    devicePermissions = "allow-all",
    remotePermissions = "allow-all",
    featureSupported = true,
    theme = "Dark",
    confirmUserActions = true,
    chainResponses = [],
    chainClosed = false,
    languageTag = "en",
    supportedChains = {
      network: "mock",
      chains: [
        { identifier: "People", genesisHash: MOCK_GENESIS.people },
        { identifier: "Bulletin", genesisHash: MOCK_GENESIS.bulletin },
        { identifier: "AssetHub", genesisHash: MOCK_GENESIS.assetHub },
      ],
    },
  } = config;

  const storage = new Map<string, Uint8Array>();
  const preimages = new Map<string, Uint8Array>();
  const navigations: string[] = [];
  const pushedNotifications: HostPushNotificationRequest[] = [];
  const sentRpc: string[] = [];
  const authStates: AuthState[] = [];
  const confirmations: string[] = [];
  const cancelledNotifications: number[] = [];
  let nextNotificationId = 0;

  // Product keys are namespaced from core slots so neither can shadow the other.
  // This in-JS key scheme is internal and independent from the Rust MockPlatform's
  // (state never crosses the boundary), so the two need not match byte-for-byte.
  const productKey = (key: string): string => `product:${key}`;
  const coreKey = (key: CoreStorageKey): string =>
    key.tag === "PermissionAuthorization"
      ? `core:permission:${key.value.productId}:${JSON.stringify(key.value.request)}`
      : `core:${key.tag}`;
  const granted = (policy: PermissionPolicy): boolean => policy === "allow-all";

  // `RequiredHostCallbacks` (each capability wrapped in `Required<…>`): every
  // optional callback must be present, so a capability added to the generated
  // surface fails `tsc` here until the mock covers it. This is the load-bearing
  // coverage guarantee. `createWasmRawCallbacks` accepts this nested shape.
  const callbacks: RequiredHostCallbacks = {
    productStorage: {
      async read(key) {
        return storage.get(productKey(key));
      },
      async write(key, value) {
        storage.set(productKey(key), value);
      },
      async clear(key) {
        storage.delete(productKey(key));
      },
    },

    coreStorage: {
      async readCoreStorage(key) {
        return storage.get(coreKey(key));
      },
      async writeCoreStorage(key, value) {
        storage.set(coreKey(key), value);
      },
      async clearCoreStorage(key) {
        storage.delete(coreKey(key));
      },
    },

    navigation: {
      async navigateTo(url) {
        navigations.push(url);
      },
    },

    notifications: {
      async pushNotification(notification) {
        pushedNotifications.push(notification);
        return { id: nextNotificationId++ };
      },
      async cancelNotification(id) {
        cancelledNotifications.push(id);
      },
    },

    permissions: {
      async devicePermission() {
        return { granted: granted(devicePermissions) };
      },
      async remotePermission() {
        return { granted: granted(remotePermissions) };
      },
    },

    features: {
      async featureSupported() {
        return { supported: featureSupported };
      },
      async supportedChains() {
        return supportedChains;
      },
    },

    chain: {
      async connect(): Promise<JsonRpcConnection> {
        return {
          send(request) {
            sentRpc.push(request);
          },
          async *responses(): AsyncGenerator<string> {
            for (const frame of chainResponses) {
              yield frame;
            }
            if (chainResponses.length === 0 && !chainClosed) {
              // Silent: never yields, so chain-dependent flows park. `chainClosed`
              // instead ends the stream here for fail-fast disconnect tests.
              await new Promise<never>(() => {});
            }
          },
          // The mock holds no real transport, so releasing the lease is a no-op.
          // Note: a Silent connection whose `responses()` stream is already parked
          // stays parked after close() — tests that need the stream to terminate use
          // `chainClosed` (or scripted frames), not close().
          close() {},
        };
      },
    },

    auth: {
      authStateChanged(state) {
        authStates.push(state);
      },
    },

    userConfirmation: {
      async confirmUserAction(review) {
        confirmations.push(review.tag);
        return confirmUserActions;
      },
    },

    theme: {
      async *subscribeTheme(): AsyncGenerator<
        Result<HostThemeSubscribeItem, GenericError>
      > {
        yield ok({ name: { tag: "Default" }, variant: theme });
        // A live subscription never ends: emit the current theme, then stay open.
        await new Promise<never>(() => {});
      },
    },

    locale: {
      async *subscribeLocale(): AsyncGenerator<
        Result<HostLocaleSubscribeItem, GenericError>
      > {
        yield ok({ languageTag });
        // A live subscription never ends, matching `subscribeTheme`.
        await new Promise<never>(() => {});
      },
    },

    preimage: {
      async *lookupPreimage(
        key,
      ): AsyncGenerator<Result<Uint8Array | undefined, GenericError>> {
        yield ok(preimages.get(hex(key)));
        // Stay open for future updates (none, in the mock).
        await new Promise<never>(() => {});
      },
    },
  };

  return {
    callbacks,
    navigations: () => [...navigations],
    pushedNotifications: () => [...pushedNotifications],
    sentRpc: () => [...sentRpc],
    authStates: () => [...authStates],
    confirmations: () => [...confirmations],
    cancelledNotifications: () => [...cancelledNotifications],
    insertPreimage(value) {
      const key = preimageKey(value);
      preimages.set(hex(key), value);
      return key;
    },
  };
}

/**
 * Genesis hashes the mock host serves, one distinct non-zero value per chain.
 *
 * Distinct matters: chain routing is keyed on the genesis hash, so equal
 * hashes make the chains indistinguishable and a chain-routed call resolves to
 * whichever entry is found first. Non-zero matters for the same reason -- an
 * all-zero hash is also the natural placeholder a caller passes by accident.
 */
export const MOCK_GENESIS = {
  people:
    "0x1111111111111111111111111111111111111111111111111111111111111111",
  bulletin:
    "0x2222222222222222222222222222222222222222222222222222222222222222",
  assetHub:
    "0x3333333333333333333333333333333333333333333333333333333333333333",
} as const;

/**
 * A default {@link ProductRuntimeConfig} for a mock host. Override any field;
 * the genesis hashes and product id are placeholders suitable for tests.
 */
export function mockRuntimeConfig(
  overrides: Partial<ProductRuntimeConfig> = {},
): ProductRuntimeConfig {
  return {
    productId: "mock.dot",
    host: {
      name: "Mock Host",
      icon: "https://example.invalid/mock.png",
      version: "0.0.0",
    },
    platform: {
      type: "node",
      version: "0",
    },
    people: { genesisHash: MOCK_GENESIS.people },
    bulletin: { genesisHash: MOCK_GENESIS.bulletin },
    assetHub: { genesisHash: MOCK_GENESIS.assetHub },
    pairing: {
      deeplinkScheme: "polkadotapp",
    },
    ...overrides,
  };
}
