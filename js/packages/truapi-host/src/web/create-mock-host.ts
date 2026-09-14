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
  ChatMessageContent,
  ChatRoom,
  GenericError,
  HostChatListSubscribeItem,
  HostChatPostMessageResponse,
  HostChatRegisterBotRequest,
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
  UserConfirmationReview,
} from "../generated/host-callbacks.js";
import type { ProductRuntimeConfig } from "../runtime.js";

/** How the mock answers a permission prompt for one capability. */
export type PermissionPolicy = "allow-all" | "deny-all";

/** Optional error injection, mirroring the Rust `MockFaults`. */
export interface MockFaults {
  /** Product and core storage reads/writes/clears fail with this reason. */
  storageError?: string;
  /** `navigateTo` fails with this reason. */
  navigateError?: string;
  /** `pushNotification` fails with this reason. */
  notificationError?: string;
  /**
   * `confirmUserAction` fails with this reason instead of answering.
   *
   * Distinct from a declined confirmation: the host could not put the question
   * to the user at all, which the core must not read as a refusal.
   */
  confirmationError?: string;
  /** Device and remote permission prompts fail with this reason. */
  permissionError?: string;
  /** `featureSupported` and `supportedChains` fail with this reason. */
  featureError?: string;
  /** Chat room, bot, and message calls fail with this reason. */
  chatError?: string;
}

/** Which prompt surface a permission decision came from. */
export type PermissionKind = "device" | "remote";

/** One permission answer the mock gave, recorded for assertions. */
export interface PermissionDecision {
  /** Which prompt surface asked. */
  kind: PermissionKind;
  /** The request's tag, the same key `grantPermission` takes. */
  permission: string;
  /** What the mock answered. */
  granted: boolean;
}

/**
 * One signing request the core put to the host.
 *
 * The signing-shaped view of {@link MockHost.reviews}: a TrUAPI host confirms
 * signatures rather than performing them, so what it sees is the review, and
 * `payload` is that review's own payload rather than a host-assembled one.
 */
export interface SigningLogEntry {
  /** Which signing request was reviewed. */
  type: "payload" | "raw" | "createTransaction";
  /** The reviewed request. */
  payload: unknown;
}

/** One chat message the product posted through the mock. */
export interface ChatMessageRecord {
  /** Id the mock assigned and returned to the product. */
  messageId: string;
  /** Room the message was posted to. */
  roomId: string;
  /** What was posted. */
  payload: ChatMessageContent;
}

/** State of the mock's chain connection, as the host sees it. */
export type ChainStatus = "Idle" | "Connected" | "Disconnected";

/**
 * A domain TrUAPI declares but no host implements.
 *
 * Reaching one throws a descriptive error rather than failing later with
 * `undefined is not a function`, and never fakes a success for a path the real
 * host cannot execute.
 */
function notModeled<T extends object>(domain: string): T {
  return new Proxy({} as T, {
    get(_target, property) {
      throw new Error(
        `${domain}.${String(property)} is not implemented in TrUAPI: ` +
          `the protocol declares ${domain} but no host implements it, so the ` +
          `mock cannot model it. See docs/rfcs/0006-payments.md.`,
      );
    },
  });
}

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
   * Error injection. When a field is set, the matching host call rejects with
   * that reason instead of succeeding.
   */
  faults?: MockFaults;
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
  getNavigationLog(): string[];
  /** Notifications the core asked the host to show, in order. */
  getNotificationLog(): HostPushNotificationRequest[];
  /** Raw JSON-RPC the core sent over the chain connection, in order. */
  sentRpc(): string[];
  /** Auth-state transitions the core emitted, in order. */
  authStates(): AuthState[];
  /**
   * Full confirmation reviews the core requested, in order.
   *
   * Carries the reviewed payload, not just its kind: a `SignRaw` review holds
   * the bytes the product asked to have signed, so a test can assert *what*
   * was put to the user rather than only that something was.
   */
  reviews(): UserConfirmationReview[];
  /** Confirmation kinds the core requested (review `tag`s), in order. */
  confirmations(): string[];
  /**
   * Signing requests the core put to the host, in order.
   *
   * A filtered view of {@link MockHost.reviews}: only the reviews that gate a
   * signature, shaped the way a signing log is usually read.
   */
  getSigningLog(): SigningLogEntry[];
  /** Whether the core has reported an authenticated session. */
  getIsAuthenticated(): boolean;
  /**
   * Whether the product-host link is up.
   *
   * The mock has no transport of its own, so this reports the chain-side
   * connection it does model; a harness owning the real product link should
   * report that instead.
   */
  getConnectionStatus(): ChainStatus;
  /** Switch the answer both permission prompts fall back to. */
  setPermissionBehavior(behavior: PermissionPolicy): void;
  /** Release the mock's state. Equivalent to {@link MockHost.reset} here. */
  dispose(): void;
  /** Permission answers the mock gave, in order. */
  getPermissionLog(): PermissionDecision[];
  /** Permissions with an explicit grant, in key order. */
  getGrantedPermissions(): string[];
  /** Answer `permission` with a grant, whatever the configured policy says. */
  grantPermission(permission: string): void;
  /** Answer `permission` with a denial, whatever the configured policy says. */
  revokePermission(permission: string): void;
  /** Drop the explicit answer for `permission`, restoring policy fallback. */
  resetPermission(permission: string): void;
  /**
   * When enforcing, deny every permission without an explicit grant instead of
   * falling back to the configured policy. Off by default.
   */
  setEnforcePermissions(enforce: boolean): void;
  /** The theme the mock currently reports. */
  getTheme(): ThemeVariant;
  /** Replace the reported theme. */
  setTheme(variant: ThemeVariant): void;
  /** State of the mock's chain connection. */
  getChainStatus(): ChainStatus;
  /** Mark the chain disconnected, as a dropped transport would. */
  simulateDisconnect(): void;
  /** Allow connections again after a simulated disconnect. */
  simulateReconnect(): void;
  /** Chat rooms the product registered. */
  getChatRooms(): ChatRoom[];
  /** Chat bots the product registered. */
  getChatBots(): HostChatRegisterBotRequest[];
  /** Messages the product posted, with the ids the mock assigned. */
  getChatMessageLog(): ChatMessageRecord[];
  /** Seeded preimage values. */
  getPreimages(): Uint8Array[];
  /** Drop the recorded navigations. */
  clearNavigationLog(): void;
  /** Drop the recorded shown and cancelled notifications. */
  clearNotificationLog(): void;
  /** Drop the recorded confirmation reviews. */
  clearSigningLog(): void;
  /** Drop the recorded permission answers, keeping explicit grants. */
  clearPermissionLog(): void;
  /** Drop every explicit permission grant and denial. */
  clearPermissionDecisions(): void;
  /** Drop the recorded auth-state transitions. */
  clearAuthStates(): void;
  /** Drop the recorded outbound JSON-RPC. */
  clearSentRpc(): void;
  /** Drop the seeded preimages. */
  clearPreimages(): void;
  /** Drop the product and core storage contents. */
  clearStorage(): void;
  /** Drop the registered rooms and bots and the posted-message log. */
  clearChatState(): void;
  /**
   * Return the mock to its freshly-constructed state, keeping its config.
   *
   * Tests reset between cases; doing it in one call is what keeps a recording
   * from one case out of the assertions of the next.
   */
  reset(): void;
  /**
   * Payments, which TrUAPI declares but no host implements. Every access
   * throws; see {@link notModeled}.
   */
  payment: never;
  /** Coin payments, unimplemented in the same way as {@link MockHost.payment}. */
  coinPayment: never;
  /** Notification ids the core asked the host to cancel, in order. */
  cancelledNotifications(): number[];
  /**
   * Seed a preimage so a later `preimage.lookupPreimage` resolves it, and
   * return the deterministic lookup key. The core (not the host) owns Bulletin
   * submission on current core; this is the host-side content store the mock's
   * `lookupPreimage` reads from.
   */
  seedPreimage(value: Uint8Array): Uint8Array;
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
    devicePermissions: devicePermissionsInitial = "allow-all",
    remotePermissions: remotePermissionsInitial = "allow-all",
    featureSupported = true,
    theme = "Dark",
    confirmUserActions = true,
    chainResponses = [],
    chainClosed = false,
    languageTag = "en",
    faults = {},
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
  const reviews: UserConfirmationReview[] = [];
  const cancelledNotifications: number[] = [];
  const permissionLog: PermissionDecision[] = [];
  const permissionDecisions = new Map<string, boolean>();
  const chatRooms = new Map<string, ChatRoom>();
  const chatBots = new Map<string, HostChatRegisterBotRequest>();
  const chatMessages: ChatMessageRecord[] = [];
  let nextNotificationId = 0;
  let nextChatMessageId = 0;
  let devicePermissions = devicePermissionsInitial;
  let remotePermissions = remotePermissionsInitial;
  let enforcePermissions = false;
  let currentTheme = theme;
  let chainStatus: ChainStatus = "Idle";

  /**
   * Answer one permission prompt and record it.
   *
   * The key is the request's tag -- `"Camera"`, `"ChainSubmit"`. This scheme is
   * internal to the JS mock and deliberately independent of the Rust
   * `MockPlatform`'s `Display` keys: no state crosses that boundary, and only
   * the method names have to agree.
   */
  const decidePermission = (
    kind: PermissionKind,
    permission: string,
    policy: PermissionPolicy,
  ): boolean => {
    const explicit = permissionDecisions.get(permission);
    const isGranted =
      explicit !== undefined
        ? explicit
        : enforcePermissions
          ? false
          : granted(policy);
    permissionLog.push({ kind, permission, granted: isGranted });
    return isGranted;
  };

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
      async devicePermission(request) {
        if (faults.permissionError) throw new Error(faults.permissionError);
        return {
          granted: decidePermission("device", request, devicePermissions),
        };
      },
      async remotePermission(request) {
        if (faults.permissionError) throw new Error(faults.permissionError);
        return {
          granted: decidePermission(
            "remote",
            request.permission.tag,
            remotePermissions,
          ),
        };
      },
    },

    features: {
      async featureSupported() {
        if (faults.featureError) throw new Error(faults.featureError);
        return { supported: featureSupported };
      },
      async supportedChains() {
        if (faults.featureError) throw new Error(faults.featureError);
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
        reviews.push(review);
        if (faults.confirmationError) throw new Error(faults.confirmationError);
        return confirmUserActions;
      },
    },

    theme: {
      async *subscribeTheme(): AsyncGenerator<
        Result<HostThemeSubscribeItem, GenericError>
      > {
        yield ok({ name: { tag: "Default" }, variant: currentTheme });
        // A live subscription never ends: emit the current theme, then stay open.
        await new Promise<never>(() => {});
      },
    },

    chat: {
      async createChatRoom(_product, request) {
        if (faults.chatError) throw new Error(faults.chatError);
        if (chatRooms.has(request.roomId)) return { status: "Exists" };
        chatRooms.set(request.roomId, {
          roomId: request.roomId,
          // A product that creates a room hosts it; a product reaching a room
          // as a bot registers the bot instead.
          participatingAs: "RoomHost",
        });
        return { status: "New" };
      },
      async registerChatBot(_product, request) {
        if (faults.chatError) throw new Error(faults.chatError);
        if (chatBots.has(request.botId)) return { status: "Exists" };
        chatBots.set(request.botId, request);
        return { status: "New" };
      },
      async postChatMessage(
        _product,
        request,
      ): Promise<HostChatPostMessageResponse> {
        if (faults.chatError) throw new Error(faults.chatError);
        // Posting to a room the product never registered is a product bug,
        // and a mock that silently accepted it would hide one.
        if (!chatRooms.has(request.roomId)) {
          throw new Error(`unknown chat room ${request.roomId}`);
        }
        const messageId = `mock-message:${nextChatMessageId++}`;
        chatMessages.push({
          messageId,
          roomId: request.roomId,
          payload: request.payload,
        });
        return { messageId };
      },
      async *subscribeChatRooms(): AsyncGenerator<
        Result<HostChatListSubscribeItem, GenericError>
      > {
        yield ok({ rooms: [...chatRooms.values()] });
        // A live subscription never ends, matching `subscribeTheme`.
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
    getNavigationLog: () => [...navigations],
    getNotificationLog: () => [...pushedNotifications],
    sentRpc: () => [...sentRpc],
    authStates: () => [...authStates],
    reviews: () => [...reviews],
    confirmations: () => reviews.map((review) => review.tag),
    getSigningLog: () =>
      reviews.flatMap((review) => {
        const type =
          review.tag === "SignRaw"
            ? ("raw" as const)
            : review.tag === "SignPayload"
              ? ("payload" as const)
              : review.tag === "CreateTransaction"
                ? ("createTransaction" as const)
                : undefined;
        return type === undefined
          ? []
          : [{ type, payload: (review as { value: unknown }).value }];
      }),
    getIsAuthenticated: () =>
      authStates.at(-1)?.tag === "Connected",
    getConnectionStatus: () => chainStatus,
    setPermissionBehavior: (behavior) => {
      devicePermissions = behavior;
      remotePermissions = behavior;
    },
    dispose() {
      this.reset();
    },
    cancelledNotifications: () => [...cancelledNotifications],
    getPermissionLog: () => [...permissionLog],
    getGrantedPermissions: () =>
      [...permissionDecisions.entries()]
        .filter(([, isGranted]) => isGranted)
        .map(([permission]) => permission)
        .sort(),
    grantPermission: (permission) => {
      permissionDecisions.set(permission, true);
    },
    revokePermission: (permission) => {
      permissionDecisions.set(permission, false);
    },
    resetPermission: (permission) => {
      permissionDecisions.delete(permission);
    },
    setEnforcePermissions: (enforce) => {
      enforcePermissions = enforce;
    },
    getTheme: () => currentTheme,
    setTheme: (variant) => {
      currentTheme = variant;
    },
    getChainStatus: () => chainStatus,
    simulateDisconnect: () => {
      chainStatus = "Disconnected";
    },
    simulateReconnect: () => {
      chainStatus = "Idle";
    },
    getChatRooms: () => [...chatRooms.values()],
    getChatBots: () => [...chatBots.values()],
    getChatMessageLog: () => [...chatMessages],
    seedPreimage(value) {
      const key = preimageKey(value);
      preimages.set(hex(key), value);
      return key;
    },
    getPreimages: () => [...preimages.values()],
    clearNavigationLog: () => {
      navigations.length = 0;
    },
    clearNotificationLog: () => {
      pushedNotifications.length = 0;
      cancelledNotifications.length = 0;
    },
    clearSigningLog: () => {
      reviews.length = 0;
    },
    clearPermissionLog: () => {
      permissionLog.length = 0;
    },
    clearPermissionDecisions: () => permissionDecisions.clear(),
    clearAuthStates: () => {
      authStates.length = 0;
    },
    clearSentRpc: () => {
      sentRpc.length = 0;
    },
    clearPreimages: () => preimages.clear(),
    clearStorage: () => storage.clear(),
    clearChatState: () => {
      chatRooms.clear();
      chatBots.clear();
      chatMessages.length = 0;
    },
    reset() {
      this.clearNavigationLog();
      this.clearNotificationLog();
      this.clearSigningLog();
      this.clearPermissionLog();
      this.clearPermissionDecisions();
      this.clearAuthStates();
      this.clearSentRpc();
      this.clearPreimages();
      this.clearStorage();
      this.clearChatState();
      currentTheme = theme;
      chainStatus = "Idle";
      enforcePermissions = false;
      nextNotificationId = 0;
      nextChatMessageId = 0;
    },
    payment: notModeled("payment"),
    coinPayment: notModeled("coinPayment"),
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
    // A signing host refuses to start without this; a pairing host ignores it.
    // Setting it unconditionally keeps one config usable for both roles.
    networkSuffix: "paseo",
    ...overrides,
  };
}
