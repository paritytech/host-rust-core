// TrUAPIHost - Android host adapter.
//
// The Rust core (compiled to `libtruapi_server.so` and surfaced via UniFFI in
// `src/main/kotlin/generated/uniffi/truapi_server/truapi_server.kt`) owns the
// wire protocol, request routing, subscription lifecycle, and platform trait
// dispatch.
//
// This file exposes:
//
//   * `HostBridge` - the Kotlin-friendly callback interface the embedding app
//     implements. It splits device and remote permissions, mirroring the
//     `Permissions` platform trait in the Rust core.
//   * `HostStorage` / `HostCoreStorage` - the product-scoped and core-owned
//     key-value backends the host persists.
//   * `TrUAPIHostCore` - owning wrapper around the UniFFI-generated
//     `NativeTrUApiCore`. Holds the bridge alive for the lifetime of the core
//     and exposes session + WS-bridge controls plus native change notifications.
//   * `LocalhostBridgeBootstrap` - JS snippet that publishes the WS bridge
//     endpoint to the product page so it can dial back in.
//
// Products running inside a `WebView` connect to the Rust core via the
// localhost WebSocket bridge. Start it with `core.startWsBridge()` and load
// the product page with a `LocalhostBridgeBootstrap.script(...)` snippet
// injected at document start so the page's `@parity/truapi`
// `createWebSocketProvider` can dial `ws://127.0.0.1:<port>/?t=<token>`.

package io.parity.truapi

import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import uniffi.truapi.ChatBotRegistrationStatus
import uniffi.truapi.ChatMessageContent
import uniffi.truapi.ChatRoom
import uniffi.truapi.ChatRoomRegistrationStatus
import uniffi.truapi.CustomRendererNode
import uniffi.truapi.HostChatActionSubscribeItem
import uniffi.truapi.HostDevicePermissionRequest
import uniffi.truapi.HostFeatureSupportedRequest
import uniffi.truapi.HostPushNotificationRequest
import uniffi.truapi.RemotePermission
import uniffi.truapi.HostThemeSubscribeItem
import uniffi.truapi.ThemeName
import uniffi.truapi.ThemeVariant
import uniffi.truapi.HostLocalStorageReadError
import uniffi.truapi.HostNavigateToError
import uniffi.truapi_platform.AuthState
import uniffi.truapi_platform.HostChainSet
import uniffi.truapi_platform.PermissionAuthorizationRequest
import uniffi.truapi_platform.PermissionAuthorizationStatus
import uniffi.truapi_platform.UserConfirmationReview
import uniffi.truapi_server.HostCallbacks
import uniffi.truapi_server.NativeChatCallbacks
import uniffi.truapi_server.NativeCustomRendererObserver
import uniffi.truapi_server.NativeProductExecution
import uniffi.truapi_server.NativeTrUApiHostRuntime
import uniffi.truapi_server.ProductRuntimeException
import uniffi.truapi_server.HostNavigateRejection
import uniffi.truapi_server.HostRejection
import uniffi.truapi_server.HostStorageException
import uniffi.truapi_platform.ProductExecutionKind as UniFfiProductExecutionKind
import uniffi.truapi_server.NativeRenewalTargetException
import uniffi.truapi_server.NativeRuntimeConfigException
import uniffi.truapi_server.NativeStatementRenewalTarget
import uniffi.truapi_server.NativeTrUApiCore
import uniffi.truapi_server.StatementRenewalReport
import uniffi.truapi_server.WsBridgeEndpoint
import uniffi.truapi_server.WsBridgeStartException
import uniffi.truapi_server.NativePairingDeeplinkScheme as UniFfiNativePairingDeeplinkScheme
import uniffi.truapi_server.NativeRuntimeConfig as UniFfiNativeRuntimeConfig
import uniffi.truapi_server.NativeHostRuntimeConfig as UniFfiNativeHostRuntimeConfig
import uniffi.truapi_server.NativeProductExecutionConfig as UniFfiNativeProductExecutionConfig

/** Package metadata. */
object TrUAPIHost {
    const val VERSION = "0.1.0"
}

/** Deeplink scheme used when the Rust core builds SSO pairing payloads. */
enum class PairingDeeplinkScheme {
    POLKADOT_APP,
    POLKADOT_APP_DEV;

    internal fun toNative(): UniFfiNativePairingDeeplinkScheme =
        when (this) {
            POLKADOT_APP -> UniFfiNativePairingDeeplinkScheme.POLKADOT_APP
            POLKADOT_APP_DEV -> UniFfiNativePairingDeeplinkScheme.POLKADOT_APP_DEV
        }
}

/** Trusted kind of executable attached to a product connection. */
enum class ProductExecutionKind {
    APP,
    WIDGET,
    WORKER;

    internal fun toNative(): UniFfiProductExecutionKind =
        when (this) {
            APP -> UniFfiProductExecutionKind.APP
            WIDGET -> UniFfiProductExecutionKind.WIDGET
            WORKER -> UniFfiProductExecutionKind.WORKER
        }
}

/**
 * Static product and pairing config supplied before the Rust core handles
 * product calls. One core instance represents one product identity.
 *
 * [hostName], [hostIcon], [hostVersion], [platformType], and [platformVersion]
 * describe the host to the wallet during SSO pairing.
 * [peopleChainGenesisHash] and [bulletinChainGenesisHash] must each be exactly
 * 32 bytes. [localSessionSecret] optionally activates a local signing session
 * from host-held BIP-39 entropy (no SSO pairing needed).
 */
data class RuntimeConfig(
    val productId: String,
    val executionKind: ProductExecutionKind = ProductExecutionKind.APP,
    val hostName: String,
    val hostIcon: String? = null,
    val hostVersion: String? = null,
    val platformType: String? = null,
    val platformVersion: String? = null,
    val peopleChainGenesisHash: ByteArray,
    val bulletinChainGenesisHash: ByteArray,
    val localSessionSecret: ByteArray? = null,
    val localSessionLiteUsername: String? = null,
    val pairingDeeplinkScheme: PairingDeeplinkScheme = PairingDeeplinkScheme.POLKADOT_APP,
) {
    internal fun toNative(): UniFfiNativeRuntimeConfig =
        UniFfiNativeRuntimeConfig(
            productId = productId,
            executionKind = executionKind.toNative(),
            hostName = hostName,
            hostIcon = hostIcon,
            hostVersion = hostVersion,
            platformType = platformType,
            platformVersion = platformVersion,
            peopleChainGenesisHash = peopleChainGenesisHash,
            bulletinChainGenesisHash = bulletinChainGenesisHash,
            localSessionSecret = localSessionSecret,
            localSessionLiteUsername = localSessionLiteUsername,
            pairingDeeplinkScheme = pairingDeeplinkScheme.toNative(),
        )

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is RuntimeConfig) return false
        return productId == other.productId &&
            executionKind == other.executionKind &&
            hostName == other.hostName &&
            hostIcon == other.hostIcon &&
            hostVersion == other.hostVersion &&
            platformType == other.platformType &&
            platformVersion == other.platformVersion &&
            peopleChainGenesisHash.contentEquals(other.peopleChainGenesisHash) &&
            bulletinChainGenesisHash.contentEquals(other.bulletinChainGenesisHash) &&
            // Compare nullability explicitly so null (no session) is distinct
            // from an empty secret (invalid input) — matching hashCode, which
            // hashes null to 0 and an empty array to 1.
            localSessionSecret.contentEquals(other.localSessionSecret) &&
            localSessionLiteUsername == other.localSessionLiteUsername &&
            pairingDeeplinkScheme == other.pairingDeeplinkScheme
    }

    override fun hashCode(): Int {
        var result = productId.hashCode()
        result = 31 * result + executionKind.hashCode()
        result = 31 * result + hostName.hashCode()
        result = 31 * result + (hostIcon?.hashCode() ?: 0)
        result = 31 * result + (hostVersion?.hashCode() ?: 0)
        result = 31 * result + (platformType?.hashCode() ?: 0)
        result = 31 * result + (platformVersion?.hashCode() ?: 0)
        result = 31 * result + peopleChainGenesisHash.contentHashCode()
        result = 31 * result + bulletinChainGenesisHash.contentHashCode()
        result = 31 * result + (localSessionSecret?.contentHashCode() ?: 0)
        result = 31 * result + (localSessionLiteUsername?.hashCode() ?: 0)
        result = 31 * result + pairingDeeplinkScheme.hashCode()
        return result
    }
}

/**
 * Immutable process-wide configuration shared by every product execution
 * opened from one [TrUAPIHostRuntime]. [peopleChainGenesisHash] and
 * [bulletinChainGenesisHash] must each be exactly 32 bytes.
 */
data class HostRuntimeConfig(
    val hostName: String,
    val hostIcon: String? = null,
    val hostVersion: String? = null,
    val platformType: String? = null,
    val platformVersion: String? = null,
    val peopleChainGenesisHash: ByteArray,
    val bulletinChainGenesisHash: ByteArray,
    val localSessionSecret: ByteArray? = null,
    val localSessionLiteUsername: String? = null,
) {
    internal fun toNative(): UniFfiNativeHostRuntimeConfig =
        UniFfiNativeHostRuntimeConfig(
            hostName = hostName,
            hostIcon = hostIcon,
            hostVersion = hostVersion,
            platformType = platformType,
            platformVersion = platformVersion,
            peopleChainGenesisHash = peopleChainGenesisHash,
            bulletinChainGenesisHash = bulletinChainGenesisHash,
            localSessionSecret = localSessionSecret,
            localSessionLiteUsername = localSessionLiteUsername,
        )

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HostRuntimeConfig) return false
        return hostName == other.hostName &&
            hostIcon == other.hostIcon &&
            hostVersion == other.hostVersion &&
            platformType == other.platformType &&
            platformVersion == other.platformVersion &&
            peopleChainGenesisHash.contentEquals(other.peopleChainGenesisHash) &&
            bulletinChainGenesisHash.contentEquals(other.bulletinChainGenesisHash) &&
            localSessionSecret.contentEquals(other.localSessionSecret) &&
            localSessionLiteUsername == other.localSessionLiteUsername
    }

    override fun hashCode(): Int {
        var result = hostName.hashCode()
        result = 31 * result + (hostIcon?.hashCode() ?: 0)
        result = 31 * result + (hostVersion?.hashCode() ?: 0)
        result = 31 * result + (platformType?.hashCode() ?: 0)
        result = 31 * result + (platformVersion?.hashCode() ?: 0)
        result = 31 * result + peopleChainGenesisHash.contentHashCode()
        result = 31 * result + bulletinChainGenesisHash.contentHashCode()
        result = 31 * result + (localSessionSecret?.contentHashCode() ?: 0)
        result = 31 * result + (localSessionLiteUsername?.hashCode() ?: 0)
        return result
    }
}

/** Host-selected identity and trusted kind for one executable connection. */
data class ProductExecutionConfig(
    val productId: String,
    val executionKind: ProductExecutionKind,
) {
    internal fun toNative(): UniFfiNativeProductExecutionConfig =
        UniFfiNativeProductExecutionConfig(
            productId = productId,
            executionKind = executionKind.toNative(),
        )
}

/**
 * Product-scoped key-value storage the host provides to the Rust core. Throws
 * [HostStorageException] to signal quota exhaustion or unknown failure; the
 * core maps both onto the v0.1 `HostLocalStorageReadError` wire shape.
 */
interface HostStorage {
    @Throws(HostStorageException::class)
    fun read(key: String): ByteArray?

    @Throws(HostStorageException::class)
    fun write(key: String, value: ByteArray)

    @Throws(HostStorageException::class)
    fun clear(key: String)
}

/**
 * Core-owned key-value storage the host backs with its own persistence. The
 * core writes auth session, pairing identity, and persisted permission
 * decisions here; [key] is a SCALE-encoded `CoreStorageKey`. Throws
 * [HostRejection] on failure.
 */
interface HostCoreStorage {
    @Throws(HostRejection::class)
    fun read(key: ByteArray): ByteArray?

    @Throws(HostRejection::class)
    fun write(key: ByteArray, value: ByteArray)

    @Throws(HostRejection::class)
    fun clear(key: ByteArray)
}

/**
 * Host-side callback bundle that the Rust core invokes for capabilities the
 * native shell owns. The interface mirrors the underlying UniFFI surface but
 * keeps the permission split explicit:
 *
 *   * [devicePermission] handles camera / mic / push prompts and similar
 *     OS-scoped grants.
 *   * [remotePermission] handles per-product capabilities requested by the
 *     application running inside the WebView.
 *
 * Embedders render the typed request values in their own UI, then report the
 * user's decision as a `Boolean`.
 *
 * Threading: the Rust core invokes every callback on a background thread it
 * owns, never the UI (main) thread. These six each run on their own thread from
 * a blocking pool, so an implementation may safely block its calling thread
 * (e.g. with a `CountDownLatch`) until the user decides; other TrUAPI traffic
 * keeps flowing: [navigateTo], [pushNotification], [devicePermission],
 * [remotePermission], [featureSupported], and [confirmUserAction]. The
 * remaining callbacks (auth state, storage, core storage, chain, theme,
 * preimage lookups, and [cancelNotification]) run inline on the dispatcher
 * thread and must return promptly without blocking. Any UI work
 * MUST still be marshalled onto the main thread, e.g. with
 * `Handler(Looper.getMainLooper()).post { ... }` or a `CoroutineScope` bound to
 * `Dispatchers.Main`. Touching views or the `WebView` directly from a callback
 * throws `CalledFromWrongThreadException`.
 */
interface HostBridge {
    /** Lifecycle logger. Marker is a stable slug, detail is free-form. */
    fun onCoreLog(marker: String, detail: String) {}

    /**
     * Open a URL in the system browser. Invoked on a blocking-pool thread;
     * marshal the UI launch (e.g. `startActivity`) to the main thread. May
     * block the calling thread if the user has to approve the navigation.
     */
    @Throws(HostNavigateRejection::class)
    suspend fun navigateTo(url: String)

    /**
     * Deliver a push notification and return the host-assigned notification
     * id. Invoked on the dispatcher thread; marshal any UI work to the main
     * thread and return promptly.
     */
    @Throws(HostRejection::class)
    suspend fun pushNotification(request: HostPushNotificationRequest): UInt = 0u

    /** Cancel a previously scheduled notification id. */
    @Throws(HostRejection::class)
    fun cancelNotification(id: UInt) {}

    /**
     * Prompt for a device-level permission. Returns whether it was granted.
     * Invoked on a blocking-pool thread; present the prompt on the main thread
     * and block the calling thread until the user decides. Blocking here does
     * not stall other TrUAPI traffic.
     */
    @Throws(HostRejection::class)
    suspend fun devicePermission(request: HostDevicePermissionRequest): Boolean

    /**
     * Prompt for a remote (product-scoped) permission bundle. Invoked on a
     * blocking-pool thread; present the prompt on the main thread and block the
     * calling thread until the user decides. Blocking here does not stall other
     * TrUAPI traffic.
     */
    @Throws(HostRejection::class)
    suspend fun remotePermission(request: RemotePermission): Boolean

    /**
     * Observe an auth state change, in transition order: render
     * [AuthState.Pairing] as the pairing QR UI, connected/disconnected as the
     * account badge, and login-failed as a retryable error, unless its kind is
     * [LoginFailureKind.NoFreeAllowanceSlots], which is unlikely to succeed
     * before the period rolls over, so retry should not be the primary action.
     * A pairing host's session activation reports its
     * outcome even when it is the default disconnected, so a host that awaits
     * activation before routing never has to read silence as "signed out";
     * every other emission, and every emission on a host role that has no
     * session activation, happens only when the state actually changes. Report
     * a user dismissal of the pairing UI through [TrUAPIHostCore.cancelLogin].
     * Invoked on the dispatcher thread; marshal the state to the main thread
     * and return promptly.
     */
    fun authStateChanged(state: AuthState) {}

    /** Open a JSON-RPC chain connection and return a host-assigned id, or null if unsupported. */
    @Throws(HostRejection::class)
    fun chainConnect(genesisHash: ByteArray): UInt? = null

    /** Send one JSON-RPC request on a native chain connection. */
    @Throws(HostRejection::class)
    fun chainSend(connectionId: UInt, request: String) {}

    /** Close a native chain connection. */
    @Throws(HostRejection::class)
    fun chainClose(connectionId: UInt) {}

    /**
     * Confirm one user-reviewed core action; the review variant picks the
     * prompt (sign payload, sign raw, create transaction, account alias,
     * resource allocation, or preimage submit). Invoked on a blocking-pool
     * thread; present the prompt on the main thread and block the calling
     * thread until the user decides.
     */
    @Throws(HostRejection::class)
    suspend fun confirmUserAction(review: UserConfirmationReview): Boolean = false

    /** Return the current preimage value for [key], or null for a miss. */
    @Throws(HostRejection::class)
    suspend fun lookupPreimage(key: ByteArray): ByteArray? = null

    /** Return the current host theme. Hosts with no named themes report [ThemeName.Default]. */
    @Throws(HostRejection::class)
    fun currentTheme(): HostThemeSubscribeItem =
        HostThemeSubscribeItem(ThemeName.Default, ThemeVariant.DARK)

    /**
     * Answer a feature-support query. Invoked on the dispatcher thread; must
     * return promptly.
     */
    @Throws(HostRejection::class)
    suspend fun featureSupported(request: HostFeatureSupportedRequest): Boolean

    /**
     * Enumerate the chains this host serves: its environment plus one entry
     * per chain role.
     */
    @Throws(HostRejection::class)
    fun supportedChains(): HostChainSet = HostChainSet(network = "", chains = emptyList())

    /** Product-scoped key-value storage for the Rust core. */
    val storage: HostStorage

    /** Core-owned key-value storage for auth session / pairing identity / permission decisions. */
    val coreStorage: HostCoreStorage
}

/**
 * Native Chat storage and UI surface. Implement and pass to
 * [TrUAPIHostRuntime.openProductExecution] when the host supports the Chat
 * modality; hosts without it pass nothing.
 *
 * Threading: these run inline on the process-wide dispatch pool shared by
 * every product execution, so implementations must be safe to enter
 * concurrently and one that blocks stalls the others. Return promptly and
 * marshal UI work to the main thread.
 */
interface ChatHostBridge {
    /**
     * Create or resolve a native product Chat room. The core has bounded and
     * normalized these arguments and screened the icon scheme; escaping them
     * for the surface that renders them is still the host's job.
     */
    @Throws(HostRejection::class)
    fun createRoom(roomId: String, name: String, icon: String): ChatRoomRegistrationStatus

    /**
     * Register or resolve a native product Chat bot. The core has bounded and
     * normalized these arguments and screened the icon scheme; escaping them
     * for the surface that renders them is still the host's job.
     */
    @Throws(HostRejection::class)
    fun registerBot(botId: String, name: String, icon: String): ChatBotRegistrationStatus

    /**
     * Persist a product-authored message in native Chat storage. Throw for a
     * content variant this host cannot render.
     *
     * The core has bounded and screened every field, but a body passes through
     * byte-for-byte and `ChatFile.sizeBytes` is an unverified product
     * assertion, so escaping and sizing remain the host's job.
     *
     * The returned id is what `ActionTrigger.messageId` carries back, so it
     * must name this message for as long as the host stores it. An id arriving
     * in a `Reaction` or `ReactionRemoved` is product-chosen and untrusted: it
     * may name a message in another room, or none at all.
     */
    @Throws(HostRejection::class)
    fun postMessage(roomId: String, content: ChatMessageContent): String

    /** Return the current product-scoped native Chat rooms. */
    @Throws(HostRejection::class)
    fun listRooms(): List<ChatRoom>
}

/**
 * Adapter from the public [HostBridge] surface to the generated UniFFI
 * [HostCallbacks] interface. Keeps the public API stable even if uniffi-bindgen
 * renames generated symbols.
 */
private class HostCallbackAdapter(private val bridge: HostBridge) : HostCallbacks {
    // The core declares this and `authStateChanged` infallible, so uniffi has
    // no error type to convert a throw into and panics -- which aborts under
    // `panic = "abort"`. Neither may let a host exception reach the FFI.
    override fun onCoreLog(marker: String, detail: String) {
        runCatching { bridge.onCoreLog(marker, detail) }
    }

    override suspend fun navigateTo(url: String) =
        withNavigateRejection { bridge.navigateTo(url) }

    override suspend fun pushNotification(request: HostPushNotificationRequest): UInt =
        withHostRejection { bridge.pushNotification(request) }

    override fun cancelNotification(id: UInt) =
        withHostRejection { bridge.cancelNotification(id) }

    override suspend fun devicePermission(request: HostDevicePermissionRequest): Boolean =
        withHostRejection { bridge.devicePermission(request) }

    override suspend fun remotePermission(request: RemotePermission): Boolean =
        withHostRejection { bridge.remotePermission(request) }

    override fun authStateChanged(state: AuthState) {
        try {
            bridge.authStateChanged(state)
        } catch (error: Throwable) {
            runCatching {
                bridge.onCoreLog("host.auth_state_changed.threw", error.stackTraceToString())
            }
        }
    }

    override fun coreStorageRead(key: ByteArray): ByteArray? =
        withHostRejection { bridge.coreStorage.read(key) }

    override fun coreStorageWrite(key: ByteArray, value: ByteArray) =
        withHostRejection { bridge.coreStorage.write(key, value) }

    override fun coreStorageClear(key: ByteArray) =
        withHostRejection { bridge.coreStorage.clear(key) }

    override fun chainConnect(genesisHash: ByteArray): UInt? =
        withHostRejection { bridge.chainConnect(genesisHash) }

    override fun chainSend(connectionId: UInt, request: String) =
        withHostRejection { bridge.chainSend(connectionId, request) }

    override fun chainClose(connectionId: UInt) =
        withHostRejection { bridge.chainClose(connectionId) }

    override suspend fun confirmUserAction(review: UserConfirmationReview): Boolean =
        withHostRejection { bridge.confirmUserAction(review) }

    override suspend fun lookupPreimage(key: ByteArray): ByteArray? =
        withHostRejection { bridge.lookupPreimage(key) }

    override fun currentTheme(): HostThemeSubscribeItem =
        withHostRejection { bridge.currentTheme() }

    override suspend fun featureSupported(request: HostFeatureSupportedRequest): Boolean =
        withHostRejection { bridge.featureSupported(request) }

    override fun supportedChains(): HostChainSet =
        withHostRejection { bridge.supportedChains() }

    override fun localStorageRead(key: String): ByteArray? =
        withStorageException { bridge.storage.read(key) }

    override fun localStorageWrite(key: String, value: ByteArray) =
        withStorageException { bridge.storage.write(key, value) }

    override fun localStorageClear(key: String) =
        withStorageException { bridge.storage.clear(key) }
}

// A host that throws an exception type its callback does not declare crosses
// the FFI as an unexpected callback error. The Rust core converts those rather
// than aborting, but the reason it receives is then a raw JVM description, so
// each adapter funnels host throws into the declared type here.

// Bounded: this reaches the product as the rejection reason, and a host
// message can carry a whole failed statement.
private fun hostRejectionReason(error: Throwable): String =
    (error.message ?: error.toString()).take(HOST_REJECTION_REASON_MAX_CHARS)

private const val HOST_REJECTION_REASON_MAX_CHARS = 256

private inline fun <T> withHostRejection(operation: () -> T): T =
    try {
        operation()
    } catch (rejection: HostRejection) {
        throw rejection
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        throw HostRejection.Rejected(hostRejectionReason(error)).apply { initCause(error) }
    }

private inline fun <T> withNavigateRejection(operation: () -> T): T =
    try {
        operation()
    } catch (rejection: HostNavigateRejection) {
        throw rejection
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        throw HostNavigateRejection.Navigate(
            HostNavigateToError.Unknown(hostRejectionReason(error)),
        ).apply { initCause(error) }
    }

private inline fun <T> withStorageException(operation: () -> T): T =
    try {
        operation()
    } catch (storage: HostStorageException) {
        throw storage
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        throw HostStorageException.Storage(
            HostLocalStorageReadError.Unknown(hostRejectionReason(error)),
        ).apply { initCause(error) }
    }

/**
 * Adapter from the public [ChatHostBridge] surface to the generated UniFFI
 * [NativeChatCallbacks] interface.
 */
private class ChatCallbackAdapter(private val bridge: ChatHostBridge) : NativeChatCallbacks {
    override fun createRoom(
        roomId: String,
        name: String,
        icon: String,
    ): ChatRoomRegistrationStatus = withHostRejection { bridge.createRoom(roomId, name, icon) }

    override fun registerBot(
        botId: String,
        name: String,
        icon: String,
    ): ChatBotRegistrationStatus = withHostRejection { bridge.registerBot(botId, name, icon) }

    override fun postMessage(roomId: String, content: ChatMessageContent): String =
        withHostRejection { bridge.postMessage(roomId, content) }

    override fun listRooms(): List<ChatRoom> = withHostRejection { bridge.listRooms() }
}

/**
 * Bootstrap helper for the native localhost WebSocket bridge that the Rust core
 * stands up via [TrUAPIHostCore.startWsBridge] when the cdylib is built with the
 * `ws-bridge` feature.
 */
object LocalhostBridgeBootstrap {
    /**
     * Returns a `<script>`-injectable snippet that publishes the endpoint
     * metadata on `window.__truapi_localhost`, the pre-resolved permission
     * decisions on `window.__truapi_policy__`, exposes the legacy
     * `window.__HOST_API_PORT__` webview transport shape, and fires a
     * `truapi-native-ready` event. Inject at document start (before the product
     * page scripts run) so the page can dial the bridge immediately.
     *
     * [webRtcAllowed] must come from `permissionAuthorizationStatus` for
     * `RemotePermission.Remote.WebRtc` — a peek, never a prompt. It is baked in
     * as a literal because the container enforces it inside the product's own
     * realm, where an asynchronous permission request would be forgeable:
     * product script can hook the primitives such a request's bookkeeping
     * relies on and resolve it itself. A settled value has nothing to steal.
     * The consequence is that a fresh grant only takes effect once the web view
     * reloads.
     *
     * The parameter is required so that every host has to answer, but a `Boolean`
     * cannot force the answer to be a real one: passing a literal `true`
     * compiles and grants WebRTC unconditionally, which is the pre-gate
     * behaviour. Nothing downstream can detect that, so read the status from the
     * core and pass what it returns. A type that only a
     * [PermissionAuthorizationStatus] could produce would make the mistake
     * unrepresentable; it is deliberately deferred until Android enforces the
     * decision at all (see the container note where the policy is published).
     */
    fun script(port: UShort, token: String, webRtcAllowed: Boolean): String {
        val url = "ws://127.0.0.1:$port/?t=$token"
        val safeUrl = jsStringLiteral(url)
        val safeToken = jsStringLiteral(token)
        // Published for the lockdown container to read, but Android does not
        // inject the container, so on Android nothing reads it and WebRTC stays
        // reachable regardless of the decision. This is a policy value, not an
        // enforcement point: it is here so the bootstrap contract matches iOS,
        // where the container is injected and does enforce it. Android
        // enforcement is tracked separately (#334 scopes the gate to iOS).
        val safeWebRtc = if (webRtcAllowed) "true" else "false"
        return """
        (function() {
          var endpoint = { url: $safeUrl, token: $safeToken };

          function createWebSocketMessagePort(url) {
            var socket = null;
            var started = false;
            var queue = [];

            var port = {
              onmessage: null,
              onmessageerror: null,

              postMessage: function(message) {
                if (socket && socket.readyState === WebSocket.OPEN) {
                  socket.send(message);
                } else {
                  queue.push(message);
                }
              },

              start: function() {
                if (started) return;
                started = true;

                socket = new WebSocket(url);
                socket.binaryType = "arraybuffer";

                socket.onopen = function() {
                  var pending = queue;
                  queue = [];
                  pending.forEach(function(message) {
                    socket.send(message);
                  });
                };

                socket.onmessage = function(event) {
                  if (typeof port.onmessage === "function") {
                    port.onmessage({ data: new Uint8Array(event.data) });
                  }
                };

                socket.onerror = function() {
                  if (typeof port.onmessageerror === "function") {
                    port.onmessageerror();
                  }
                };

                socket.onclose = function() {
                  if (typeof port.onmessageerror === "function") {
                    port.onmessageerror();
                  }
                };
              },

              close: function() {
                queue = [];
                if (socket) {
                  socket.close();
                }
              }
            };

            return port;
          }

          window.__truapi_localhost = endpoint;
          window.__truapi_policy__ = { webRtcAllowed: $safeWebRtc };
          window.__HOST_WEBVIEW_MARK__ = true;
          window.__HOST_API_PORT__ = createWebSocketMessagePort(endpoint.url);
          window.dispatchEvent(new Event('truapi-native-ready'));
        })();
        """.trimIndent()
    }

    /**
     * Encodes [value] as a complete double-quoted JavaScript string literal,
     * safe to embed inside a `<script>` body. Escapes quotes, backslashes,
     * control characters, `/` (closing `</script` tags), and the U+2028 /
     * U+2029 line terminators that JS treats as newlines.
     */
    private fun jsStringLiteral(value: String): String {
        val sb = StringBuilder(value.length + 2)
        sb.append('"')
        for (ch in value) {
            when (ch.code) {
                '"'.code -> sb.append("\\\"")
                '\\'.code -> sb.append("\\\\")
                '/'.code -> sb.append("\\/")
                0x0A -> sb.append("\\n")
                0x0D -> sb.append("\\r")
                0x09 -> sb.append("\\t")
                0x08 -> sb.append("\\b")
                0x0C -> sb.append("\\f")
                0x2028 -> sb.append("\\u2028")
                0x2029 -> sb.append("\\u2029")
                else ->
                    if (ch.code < 0x20) {
                        sb.append("\\u")
                        sb.append(ch.code.toString(16).padStart(4, '0'))
                    } else {
                        sb.append(ch)
                    }
            }
        }
        sb.append('"')
        return sb.toString()
    }
}

/**
 * Owning wrapper around the Rust-backed [NativeTrUApiCore]. Holds the bridge
 * alive for the lifetime of the core and exposes core lifecycle + WS-bridge
 * controls plus native change notifications.
 *
 * Hosts integrating with a `WebView`-based product call [startWsBridge] and
 * inject a [LocalhostBridgeBootstrap.script] snippet at document start so the
 * product's `@parity/truapi` `createWebSocketProvider` dials
 * `ws://127.0.0.1:<port>/?t=<token>`.
 */
class TrUAPIHostCore private constructor(
    bridge: HostBridge,
    runtimeConfig: UniFfiNativeRuntimeConfig,
) : AutoCloseable {
    @Throws(NativeRuntimeConfigException::class)
    constructor(bridge: HostBridge, runtimeConfig: RuntimeConfig) : this(
        bridge,
        runtimeConfig.toNative(),
    )

    // Co-owns the adapter alongside the generated FfiConverter handle map,
    // which is what actually keeps the callback object alive for the core.
    private val callbackRetainer: HostCallbacks = HostCallbackAdapter(bridge)
    private val inner: NativeTrUApiCore =
        NativeTrUApiCore.withRuntimeConfig(callbackRetainer, runtimeConfig)

    /**
     * Start the localhost WebSocket bridge (requires the `ws-bridge` feature in
     * the cdylib). The returned [WsBridgeEndpoint] carries the port and session
     * token; feed them to [LocalhostBridgeBootstrap.script] to hand the URL to
     * the product page.
     */
    @Throws(WsBridgeStartException::class)
    fun startWsBridge(bindPort: UShort = 0u): WsBridgeEndpoint =
        inner.startWsBridge(bindPort)

    /** Stop the localhost WebSocket bridge (if running). */
    fun stopWsBridge() {
        inner.stopWsBridge()
    }

    /**
     * Core-owned logout/disconnect path. Best-effort notifies the SSO peer,
     * clears in-memory session state, and clears persisted session state via
     * the core-storage backend.
     */
    fun disconnect() {
        inner.disconnect()
    }

    /** Notify the core that host-global session storage changed externally. */
    fun notifySessionStoreChanged() {
        inner.notifySessionStoreChanged()
    }

    /**
     * Cancel any in-flight login pairing (e.g. the user dismissed the pairing
     * UI). The bridge receives a disconnected auth state immediately and the
     * pending login resolves as rejected. A no-op when no login is in progress.
     */
    fun cancelLogin() {
        inner.cancelLogin()
    }

    /**
     * Activate or replace the local signing-host session from host-held secret
     * material (raw BIP-39 entropy). Lets the host run without SSO pairing.
     */
    @Throws(HostRejection::class)
    fun activateLocalSession(secret: ByteArray, liteUsername: String? = null) {
        inner.activateLocalSession(secret, liteUsername)
    }

    /**
     * Record the accounts renewal should keep allowed on the Statement Store.
     * Needs an active session, so call it after [activateLocalSession] or after
     * pairing, not at construction.
     *
     * The ledger is append-only: there is no untrack, and a target is only
     * dropped when the identity that promised it changes. Recipe-shaped targets
     * survive that; a raw [NativeStatementRenewalTarget.Account] does not, so
     * re-track those whenever the active identity changes.
     */
    @Throws(NativeRenewalTargetException::class)
    fun trackStatementRenewalTargets(targets: List<NativeStatementRenewalTarget>) {
        inner.trackStatementRenewalTargets(targets)
    }

    /**
     * Run one renewal pass now, reporting what each tracked target got.
     *
     * Submits extrinsics and blocks until they are included, so call it from a
     * WorkManager worker rather than the main thread. There is no cancellation:
     * a pass with several targets can outlast a short background budget, though
     * a target registered before the process is killed is not lost and reads
     * back as already allocated.
     */
    @Throws(HostRejection::class)
    fun renewStatementAllowances(): StatementRenewalReport = inner.renewStatementAllowances()

    /**
     * Start the in-process renewal loop, for a host that stays resident. A
     * suspended app stops ticking, so prefer scheduling
     * [renewStatementAllowances].
     */
    fun startStatementAllowanceRenewal() {
        inner.startStatementAllowanceRenewal()
    }

    /**
     * The in-process loop's own cadence, capped at an hour. Allowances only
     * stop being renewed at a period boundary and survive it by the chain's
     * grace window, so a host scheduling one wake-up per period
     * should read a value under an hour as the boundary approaching rather than
     * waking hourly.
     */
    fun nextStatementRenewalDelay(): java.time.Duration = inner.nextStatementRenewalDelay()

    /**
     * The most recent pass the in-process renewal loop ran.
     *
     * `null` until a pass has run, which is "not yet" rather than healthy.
     * [startStatementAllowanceRenewal] returns nothing, so a host driving the loop
     * reads its result here. `slotsExhausted` on the last pass means a period
     * filled up and an allowance went unrenewed, which retrying cannot fix and a
     * person may need telling about.
     */
    fun lastStatementRenewalReport(): StatementRenewalReport? = inner.lastStatementRenewalReport()

    /** Read a stored permission authorization status without prompting. */
    @Throws(HostRejection::class)
    fun permissionAuthorizationStatus(
        request: PermissionAuthorizationRequest,
    ): PermissionAuthorizationStatus =
        inner.permissionAuthorizationStatus(request)

    /**
     * Update a stored permission authorization status. Passing `NotDetermined`
     * clears the stored value so the next product request prompts again.
     */
    @Throws(HostRejection::class)
    fun setPermissionAuthorizationStatus(
        request: PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) {
        inner.setPermissionAuthorizationStatus(request, status)
    }

    /** Push a host theme update to active TrUAPI theme subscriptions. */
    fun notifyThemeChanged(theme: HostThemeSubscribeItem) {
        inner.notifyThemeChanged(theme)
    }

    /** Push a preimage lookup update to active subscriptions for [key]. */
    fun notifyPreimageChanged(key: ByteArray, value: ByteArray?) {
        inner.notifyPreimageChanged(key, value)
    }

    /** Push a JSON-RPC response from a native chain connection into the core. */
    fun notifyChainResponse(connectionId: UInt, json: String) {
        inner.notifyChainResponse(connectionId, json)
    }

    /** Notify the core that a native chain connection closed externally. */
    fun notifyChainClosed(connectionId: UInt) {
        inner.notifyChainClosed(connectionId)
    }

    override fun close() {
        inner.close()
    }
}

/**
 * Process-owned Rust host runtime. Product executables open independent
 * connections from this object and share its authentication and core services.
 */
class TrUAPIHostRuntime private constructor(
    bridge: HostBridge,
    runtimeConfig: UniFfiNativeHostRuntimeConfig,
) : AutoCloseable {
    @Throws(NativeRuntimeConfigException::class)
    constructor(bridge: HostBridge, runtimeConfig: HostRuntimeConfig) : this(
        bridge,
        runtimeConfig.toNative(),
    )

    // Co-owns the adapter alongside the generated FfiConverter handle map,
    // which is what actually keeps the callback object alive for the runtime.
    private val callbackRetainer: HostCallbacks = HostCallbackAdapter(bridge)
    private val inner: NativeTrUApiHostRuntime =
        NativeTrUApiHostRuntime.withRuntimeConfig(callbackRetainer, runtimeConfig)

    /**
     * Open one executable connection with a host-assigned immutable context.
     * Pass [chat] to install the host's Chat adapter; hosts without the Chat
     * modality omit it.
     */
    @Throws(NativeRuntimeConfigException::class)
    fun openProductExecution(
        bridge: HostBridge,
        configuration: ProductExecutionConfig,
        chat: ChatHostBridge? = null,
    ): TrUAPIProductExecution {
        val adapter = HostCallbackAdapter(bridge)
        val chatAdapter = chat?.let { ChatCallbackAdapter(it) }
        val execution = inner.openProductExecution(adapter, chatAdapter, configuration.toNative())
        return TrUAPIProductExecution(execution, adapter, chatAdapter)
    }

    /** Core-owned logout for the process-wide authentication session. */
    fun disconnect() {
        inner.disconnect()
    }

    /** Activate or replace the process-wide local signing session. */
    @Throws(HostRejection::class)
    fun activateLocalSession(secret: ByteArray, liteUsername: String? = null) {
        inner.activateLocalSession(secret, liteUsername)
    }

    /** Push a JSON-RPC response from a native chain connection into the runtime. */
    fun notifyChainResponse(connectionId: UInt, json: String) {
        inner.notifyChainResponse(connectionId, json)
    }

    /** Notify the runtime that a native chain connection closed externally. */
    fun notifyChainClosed(connectionId: UInt) {
        inner.notifyChainClosed(connectionId)
    }

    /**
     * Record the accounts renewal should keep allowed on the Statement Store.
     * Needs an active session, so call it after [activateLocalSession] or after
     * pairing, not at construction.
     *
     * Recipe-shaped targets survive a change of root entropy; a raw
     * [NativeStatementRenewalTarget.Account] does not, so re-track those
     * whenever the active identity changes.
     */
    @Throws(NativeRenewalTargetException::class)
    fun trackStatementRenewalTargets(targets: List<NativeStatementRenewalTarget>) {
        inner.trackStatementRenewalTargets(targets)
    }

    /**
     * Run one renewal pass now, reporting what each tracked target got. Submits
     * extrinsics and blocks until they are included, so call it from a
     * WorkManager worker rather than the main thread.
     */
    @Throws(HostRejection::class)
    fun renewStatementAllowances(): StatementRenewalReport = inner.renewStatementAllowances()

    /**
     * Start the in-process renewal loop, for a host that stays resident. A
     * suspended app stops ticking, so prefer scheduling
     * [renewStatementAllowances].
     */
    fun startStatementAllowanceRenewal() {
        inner.startStatementAllowanceRenewal()
    }

    /**
     * The in-process loop's own cadence, capped at an hour. A host scheduling
     * one wake-up per period should read a value under an hour as the boundary
     * approaching rather than waking hourly.
     */
    fun nextStatementRenewalDelay(): java.time.Duration = inner.nextStatementRenewalDelay()

    override fun close() {
        inner.close()
    }
}

/**
 * One SPA or Chat executable connected to a shared [TrUAPIHostRuntime]. Closing
 * it shuts the connection down permanently; the runtime stays usable.
 */
class TrUAPIProductExecution internal constructor(
    private val inner: NativeProductExecution,
    private val callbackRetainer: HostCallbacks,
    private val chatRetainer: NativeChatCallbacks?,
) : AutoCloseable {
    private val shutDown = AtomicBoolean(false)

    /** Start this execution's independently authenticated localhost bridge. */
    @Throws(WsBridgeStartException::class)
    fun startWsBridge(bindPort: UShort = 0u): WsBridgeEndpoint = inner.startWsBridge(bindPort)

    /** Stop the active bridge while leaving the execution reusable. */
    fun stopWsBridge() {
        inner.stopWsBridge()
    }

    /**
     * Publish one native Chat action, buffering it until the product
     * connection subscribes.
     */
    @Throws(ProductRuntimeException::class)
    fun publishChatAction(action: HostChatActionSubscribeItem) {
        inner.publishChatAction(action)
    }

    /**
     * Republish the product-scoped native Chat room list. Call it whenever the
     * host's own rooms change, including when a host joins a registered bot to
     * a room.
     */
    fun notifyChatRoomsChanged(rooms: List<ChatRoom>) {
        inner.notifyChatRoomsChanged(rooms)
    }

    /**
     * Request typed native UI for one stored custom Chat message. The flow
     * subscribes on collection, so a closed or non-Chat execution fails the
     * collector with [ProductRuntimeException] rather than this call. It
     * cancels the renderer when collection ends;
     * each emission is a complete replacement tree, so only the latest is kept
     * when the collector falls behind.
     */
    fun renderCustomMessage(
        messageId: String,
        messageType: String,
        payload: ByteArray,
    ): Flow<CustomRendererNode> =
        callbackFlow {
            val observer =
                object : NativeCustomRendererObserver {
                    // The core declares both infallible, so uniffi has no error
                    // type to convert a throw into and panics -- which aborts
                    // under `panic = "abort"`.
                    override fun onUpdate(node: CustomRendererNode) {
                        runCatching { trySend(node) }
                    }

                    override fun onComplete() {
                        runCatching { close() }
                    }
                }
            val subscription = inner.renderCustomMessage(messageId, messageType, payload, observer)
            awaitClose {
                subscription.cancel()
                subscription.close()
            }
        }.conflate()

    /** Read the active session's X25519 chat identity private key, if any. */
    @Throws(HostRejection::class)
    fun sessionChatIdentityKey(): ByteArray? = inner.sessionChatIdentityKey()

    /** Read a stored permission authorization status without prompting. */
    @Throws(HostRejection::class)
    fun permissionAuthorizationStatus(
        request: PermissionAuthorizationRequest,
    ): PermissionAuthorizationStatus = inner.permissionAuthorizationStatus(request)

    /**
     * Update a stored permission authorization status. Passing `NotDetermined`
     * clears the stored value so the next product request prompts again.
     */
    @Throws(HostRejection::class)
    fun setPermissionAuthorizationStatus(
        request: PermissionAuthorizationRequest,
        status: PermissionAuthorizationStatus,
    ) {
        inner.setPermissionAuthorizationStatus(request, status)
    }

    /** Push a host theme update to active TrUAPI theme subscriptions. */
    fun notifyThemeChanged(theme: HostThemeSubscribeItem) {
        inner.notifyThemeChanged(theme)
    }

    /** Push a preimage lookup update to active subscriptions for [key]. */
    fun notifyPreimageChanged(key: ByteArray, value: ByteArray?) {
        inner.notifyPreimageChanged(key, value)
    }

    /** Push a JSON-RPC response from a native chain connection into the core. */
    fun notifyChainResponse(connectionId: UInt, json: String) {
        inner.notifyChainResponse(connectionId, json)
    }

    /** Notify the core that a native chain connection closed externally. */
    fun notifyChainClosed(connectionId: UInt) {
        inner.notifyChainClosed(connectionId)
    }

    @Synchronized
    override fun close() {
        // `shutdown` goes through the generated call guard, which throws once
        // the handle is freed, so a repeat close must not reach it. Serialized
        // as well as guarded: a concurrent close could otherwise free the
        // handle between the guard and the call.
        if (shutDown.compareAndSet(false, true)) {
            inner.shutdown()
        }
        inner.close()
    }
}
