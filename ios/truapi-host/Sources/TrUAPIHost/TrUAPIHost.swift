// TrUAPIHost - iOS host adapter.
//
// The Rust core (compiled to `libtruapi_server`, surfaced through UniFFI in
// the sibling `truapi_server.swift` file) owns wire decoding, request
// routing, subscription lifecycle, and platform trait dispatch.
//
// This file exposes:
//
//   * `TrUAPIHostCore` - owning wrapper around the UniFFI-generated
//     `NativeTrUApiCore`. Takes `HostCallbacks` directly and exposes
//     session + WS-bridge controls.
//   * `LocalhostBridgeBootstrap` - small JS snippet that publishes the WS
//     bridge endpoint to the product page so it can dial back in.
//
// Products running inside a `WKWebView` connect to the Rust core via the
// localhost WebSocket bridge. The bootstrap script publishes the URL
// (`ws://127.0.0.1:<port>/?t=<token>`) and a MessagePort-shaped compatibility
// object that proxies the product's existing webview transport onto it.

import Foundation

/// Package metadata.
public enum TrUAPIHost {
    public static let version = "0.1.0"
}

/// Deeplink scheme used when the Rust core builds SSO pairing payloads.
public enum PairingDeeplinkScheme: Sendable {
    case polkadotApp
    case polkadotAppDev

    fileprivate var native: NativePairingDeeplinkScheme {
        switch self {
        case .polkadotApp:
            return .polkadotApp
        case .polkadotAppDev:
            return .polkadotAppDev
        }
    }
}

/// Trusted kind of executable attached to a product connection.
public enum ProductExecutionKind: Sendable, Equatable {
    case spa
    case chat

    fileprivate var native: NativeProductExecutionKind {
        switch self {
        case .spa: .spa
        case .chat: .chat
        }
    }
}

/// Static product and pairing config supplied before the Rust core handles
/// product calls. One core instance represents one product identity.
///
/// `hostName`, `hostIcon`, `hostVersion`, `platformType`, and
/// `platformVersion` describe the host to the wallet during SSO pairing.
/// `peopleChainGenesisHash` and `bulletinChainGenesisHash` must each be
/// exactly 32 bytes.
public struct RuntimeConfig: Sendable {
    public let productId: String
    public let executionKind: ProductExecutionKind
    public let hostName: String
    public let hostIcon: String?
    public let hostVersion: String?
    public let platformType: String?
    public let platformVersion: String?
    public let peopleChainGenesisHash: Data
    public let bulletinChainGenesisHash: Data
    public let localSessionSecret: Data?
    public let localSessionLiteUsername: String?
    public let pairingDeeplinkScheme: PairingDeeplinkScheme

    public init(
        productId: String,
        executionKind: ProductExecutionKind = .spa,
        hostName: String,
        hostIcon: String? = nil,
        hostVersion: String? = nil,
        platformType: String? = nil,
        platformVersion: String? = nil,
        peopleChainGenesisHash: Data,
        bulletinChainGenesisHash: Data,
        localSessionSecret: Data? = nil,
        localSessionLiteUsername: String? = nil,
        pairingDeeplinkScheme: PairingDeeplinkScheme = .polkadotApp
    ) {
        self.productId = productId
        self.executionKind = executionKind
        self.hostName = hostName
        self.hostIcon = hostIcon
        self.hostVersion = hostVersion
        self.platformType = platformType
        self.platformVersion = platformVersion
        self.peopleChainGenesisHash = peopleChainGenesisHash
        self.bulletinChainGenesisHash = bulletinChainGenesisHash
        self.localSessionSecret = localSessionSecret
        self.localSessionLiteUsername = localSessionLiteUsername
        self.pairingDeeplinkScheme = pairingDeeplinkScheme
    }

    fileprivate var native: NativeRuntimeConfig {
        NativeRuntimeConfig(
            productId: productId,
            executionKind: executionKind.native,
            hostName: hostName,
            hostIcon: hostIcon,
            hostVersion: hostVersion,
            platformType: platformType,
            platformVersion: platformVersion,
            peopleChainGenesisHash: peopleChainGenesisHash,
            bulletinChainGenesisHash: bulletinChainGenesisHash,
            localSessionSecret: localSessionSecret,
            localSessionLiteUsername: localSessionLiteUsername,
            pairingDeeplinkScheme: pairingDeeplinkScheme.native
        )
    }
}

/// Immutable process-wide configuration shared by all product executions.
public struct HostRuntimeConfig: Sendable, Equatable {
    public let hostName: String
    public let hostIcon: String?
    public let hostVersion: String?
    public let platformType: String?
    public let platformVersion: String?
    public let peopleChainGenesisHash: Data
    public let bulletinChainGenesisHash: Data
    public let localSessionSecret: Data?
    public let localSessionLiteUsername: String?

    public init(
        hostName: String,
        hostIcon: String? = nil,
        hostVersion: String? = nil,
        platformType: String? = nil,
        platformVersion: String? = nil,
        peopleChainGenesisHash: Data,
        bulletinChainGenesisHash: Data,
        localSessionSecret: Data? = nil,
        localSessionLiteUsername: String? = nil
    ) {
        self.hostName = hostName
        self.hostIcon = hostIcon
        self.hostVersion = hostVersion
        self.platformType = platformType
        self.platformVersion = platformVersion
        self.peopleChainGenesisHash = peopleChainGenesisHash
        self.bulletinChainGenesisHash = bulletinChainGenesisHash
        self.localSessionSecret = localSessionSecret
        self.localSessionLiteUsername = localSessionLiteUsername
    }

    fileprivate var native: NativeHostRuntimeConfig {
        NativeHostRuntimeConfig(
            hostName: hostName,
            hostIcon: hostIcon,
            hostVersion: hostVersion,
            platformType: platformType,
            platformVersion: platformVersion,
            peopleChainGenesisHash: peopleChainGenesisHash,
            bulletinChainGenesisHash: bulletinChainGenesisHash,
            localSessionSecret: localSessionSecret,
            localSessionLiteUsername: localSessionLiteUsername
        )
    }
}

/// Host-selected identity and trusted kind for one executable connection.
public struct ProductExecutionConfig: Sendable, Equatable {
    public let productId: String
    public let executionKind: ProductExecutionKind

    public init(productId: String, executionKind: ProductExecutionKind) {
        self.productId = productId
        self.executionKind = executionKind
    }

    fileprivate var native: NativeProductExecutionConfig {
        NativeProductExecutionConfig(
            productId: productId,
            executionKind: executionKind.native
        )
    }
}

/// Bootstrap helper for the native localhost WebSocket bridge that the Rust
/// core stands up via `NativeTrUApiCore.startWsBridge(bindPort:)` when the
/// cdylib is built with the `ws-bridge` feature.
public enum LocalhostBridgeBootstrap {
    /// Returns a `<script>`-injectable snippet that publishes the endpoint
    /// metadata on `window.__truapi_localhost`, exposes the legacy
    /// `window.__HOST_API_PORT__` webview transport shape, and fires a
    /// `truapi-native-ready` event.
    public static func script(port: UInt16, token: String) -> String {
        let url = "ws://127.0.0.1:\(port)/?t=\(token)"
        let safeUrl = jsStringLiteral(url)
        let safeToken = jsStringLiteral(token)
        return """
        (function() {
          var endpoint = { url: \(safeUrl), token: \(safeToken) };

          function createWebSocketMessagePort(url) {
            var socket = null;
            var started = false;
            var queue = [];

            var port = {
              onmessage: null,
              onmessageerror: null,

              postMessage: function(message) {
                if (!started) {
                  port.start();
                }

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
          window.__HOST_WEBVIEW_MARK__ = true;
          window.__HOST_API_PORT__ = createWebSocketMessagePort(endpoint.url);
          window.dispatchEvent(new Event('truapi-native-ready'));
        })();
        """
    }

    /// Encodes `value` as a complete double-quoted JavaScript string literal,
    /// safe to embed inside a `<script>` body. `JSONEncoder` escapes quotes,
    /// backslashes, control characters, and forward slashes (closing `</script`
    /// tags); U+2028 / U+2029 are escaped explicitly because JSON leaves them
    /// raw while JS treats them as line terminators. Falls back to an empty
    /// literal if encoding ever fails.
    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return encoded
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

/// Session + WS-bridge controls of the Rust core, abstracted so hosts and
/// runtimes can depend on the interface (and tests can mock it) without
/// booting the Rust cdylib.
public protocol TrUAPIHostCoreProtocol: AnyObject {
    func startWsBridge(bindPort: UInt16) throws -> WsBridgeEndpoint
    func stopWsBridge()
    func disconnect()
    func cancelLogin()
    func activateLocalSession(secret: Data, liteUsername: String?) throws
    func permissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest
    ) throws -> NativePermissionAuthorizationStatus
    func setPermissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest,
        status: NativePermissionAuthorizationStatus
    ) throws
    func notifyThemeChanged(theme: HostTheme)
    func notifyPreimageChanged(key: Data, value: Data?)
    func notifyChainResponse(connectionId: UInt32, json: String)
    func notifyChainClosed(connectionId: UInt32)
}

/// Product-scoped key-value storage provided by the embedding host.
public protocol HostStorageBackend: AnyObject, Sendable {
    func read(key: String) throws -> Data?
    func write(key: String, value: Data) throws
    func clear(key: String) throws
}

/// Core-owned host-private storage backend. Keys are SCALE-encoded
/// `truapi_platform::CoreStorageKey` values, so embedders can persist them
/// opaquely or decode them to choose a secure backing store per slot.
public protocol HostCoreStorageBackend: AnyObject, Sendable {
    func read(key: Data) throws -> Data?
    func write(key: Data, value: Data) throws
    func clear(key: Data) throws
}

/// Host-side callback bundle that the Rust core invokes for capabilities the
/// native shell owns. The permission split mirrors the Rust `Permissions`
/// trait:
///
///   * ``devicePermission(request:)`` handles OS-scoped grants (camera,
///     mic, location).
///   * ``remotePermission(request:)`` handles per-product capability
///     bundles.
///
/// Threading: the Rust core invokes every callback on a background thread it
/// owns, never the main thread. These six each run on their own thread from a
/// blocking pool, so an implementation may safely block its calling thread
/// (e.g. with `DispatchQueue.main.sync` or a semaphore) until the user
/// decides; other TrUAPI traffic keeps flowing: ``navigateTo(url:)``,
/// ``pushNotification(payload:)``, ``devicePermission(request:)``,
/// ``remotePermission(request:)``, ``featureSupported(request:)``, and
/// ``confirmUserAction(review:)``.
/// The remaining callbacks (auth state, storage, core storage, chain, theme,
/// preimage lookups, and ``cancelNotification(id:)``) run inline on the
/// dispatcher thread and must return promptly without blocking.
/// Any UI work MUST still hop to the main thread, e.g.
/// `await MainActor.run { ... }` or `DispatchQueue.main.async { ... }`. Calling
/// UIKit/WebKit off the main thread is undefined behaviour.
public protocol HostBridge: AnyObject, Sendable {
    /// Lifecycle logger. Marker is a stable slug, detail is free-form.
    func onCoreLog(marker: String, detail: String)

    /// Open a URL in the system browser. Invoked on a blocking-pool thread;
    /// hop to the main thread to present UI. May block the calling thread if
    /// the user has to approve the navigation.
    func navigateTo(url: String) async throws

    /// Deliver a push notification (SCALE-encoded `HostPushNotificationRequest`)
    /// and return the host-assigned notification id. Invoked on the dispatcher
    /// thread; hop to the main thread for any UI work and return promptly.
    func pushNotification(request: PushNotificationRequest) async throws -> UInt32

    /// Cancel a previously scheduled notification id.
    func cancelNotification(id: UInt32) throws

    /// Prompt for a device-level permission. Returns the granted flag. Invoked
    /// on a blocking-pool thread; present the prompt on the main thread and
    /// block the calling thread until the user decides. Blocking here does
    /// not stall other TrUAPI traffic.
    func devicePermission(request: NativeDevicePermission) async throws -> Bool

    /// Prompt for a remote (product-scoped) permission bundle. Invoked on a
    /// blocking-pool thread; present the prompt on the main thread and block
    /// the calling thread until the user decides. Blocking here does not
    /// stall other TrUAPI traffic.
    func remotePermission(request: NativeRemotePermission) async throws -> Bool

    /// Observe an auth state change. The core emits states only when they
    /// actually change, in transition order: render `.pairing` as the pairing
    /// QR UI, `.connected`/`.disconnected` as the account badge, and
    /// `.loginFailed` as a retryable error. Report a user dismissal of the
    /// pairing UI through ``TrUAPIHostCore/cancelLogin()``. Invoked on the
    /// dispatcher thread; hand the state to the main thread and return
    /// promptly.
    func authStateChanged(state: AuthState)

    /// Open a JSON-RPC chain connection and return a host-assigned id, or nil if unsupported.
    func chainConnect(genesisHash: Data) throws -> UInt32?

    /// Send one JSON-RPC request on a native chain connection.
    func chainSend(connectionId: UInt32, request: String) throws

    /// Close a native chain connection.
    func chainClose(connectionId: UInt32) throws

    /// Confirm one user-reviewed core action before it continues.
    func confirmUserAction(review: NativeUserConfirmationReview) async throws -> Bool

    /// Return the current preimage value for `key`, or nil for a miss.
    func lookupPreimage(key: Data) async throws -> Data?

    /// Return the current host theme.
    func currentTheme() throws -> HostTheme

    /// Answer a feature-support query. Invoked on the dispatcher thread; must
    /// return promptly.
    func featureSupported(request: FeatureSupportedRequest) async throws -> Bool

    /// Scoped key-value storage for the Rust core.
    var storage: HostStorageBackend { get }

    /// Core-owned host-private storage for auth session, pairing identity,
    /// and persisted permission decisions.
    var coreStorage: HostCoreStorageBackend { get }

    /// Whether this host installs native Chat storage and UI callbacks.
    var supportsChat: Bool { get }

    /// Create or resolve a native product Chat room.
    func chatCreateRoom(roomId: String, name: String, icon: String) throws
        -> NativeChatRoomRegistrationStatus

    /// Persist a text message in native Chat storage.
    func chatPostTextMessage(roomId: String, text: String) throws -> String

    /// Persist a custom message in native Chat storage.
    func chatPostCustomMessage(
        roomId: String,
        messageType: String,
        payload: Data
    ) throws -> String

    /// Return the current product-scoped native Chat rooms.
    func chatListRooms() throws -> [NativeChatRoom]
}

public extension HostBridge {
    /// Default no-op logger. Override to plumb into your logging framework.
    func onCoreLog(marker: String, detail: String) {}
    func pushNotification(request: PushNotificationRequest) async throws -> UInt32 { 0 }
    func cancelNotification(id: UInt32) throws {}
    func authStateChanged(state: AuthState) {}
    func chainConnect(genesisHash: Data) throws -> UInt32? { nil }
    func chainSend(connectionId: UInt32, request: String) throws {}
    func chainClose(connectionId: UInt32) throws {}
    func confirmUserAction(review: NativeUserConfirmationReview) async throws -> Bool { false }
    func lookupPreimage(key: Data) async throws -> Data? { nil }
    func currentTheme() throws -> HostTheme { .dark }
    var supportsChat: Bool { false }
    func chatCreateRoom(
        roomId: String,
        name: String,
        icon: String
    ) throws -> NativeChatRoomRegistrationStatus {
        throw HostRejection.Rejected(reason: "native Chat adapter unavailable")
    }
    func chatPostTextMessage(roomId: String, text: String) throws -> String {
        throw HostRejection.Rejected(reason: "native Chat adapter unavailable")
    }
    func chatPostCustomMessage(
        roomId: String,
        messageType: String,
        payload: Data
    ) throws -> String {
        throw HostRejection.Rejected(reason: "native Chat adapter unavailable")
    }
    func chatListRooms() throws -> [NativeChatRoom] { [] }
}

/// Adapter that bridges the public `HostBridge` to the generated UniFFI
/// `HostCallbacks` protocol. Kept private so the generated names never
/// leak into consumers.
private final class HostCallbackAdapter: HostCallbacks, @unchecked Sendable {
    private let bridge: HostBridge

    init(bridge: HostBridge) {
        self.bridge = bridge
    }

    func onCoreLog(marker: String, detail: String) {
        bridge.onCoreLog(marker: marker, detail: detail)
    }

    func navigateTo(url: String) async throws {
        try await withNavigationRejection {
            try await bridge.navigateTo(url: url)
        }
    }

    func pushNotification(request: PushNotificationRequest) async throws -> UInt32 {
        try await withHostRejection {
            try await bridge.pushNotification(request: request)
        }
    }

    func cancelNotification(id: UInt32) throws {
        try withHostRejection {
            try bridge.cancelNotification(id: id)
        }
    }

    func devicePermission(request: NativeDevicePermission) async throws -> Bool {
        try await withHostRejection {
            try await bridge.devicePermission(request: request)
        }
    }

    func remotePermission(request: NativeRemotePermission) async throws -> Bool {
        try await withHostRejection {
            try await bridge.remotePermission(request: request)
        }
    }

    func authStateChanged(state: AuthState) {
        bridge.authStateChanged(state: state)
    }

    func coreStorageRead(key: Data) throws -> Data? {
        try withHostRejection {
            try bridge.coreStorage.read(key: key)
        }
    }

    func coreStorageWrite(key: Data, value: Data) throws {
        try withHostRejection {
            try bridge.coreStorage.write(key: key, value: value)
            LiveSessionStoreForwarder.notifySessionStoreChanged()
        }
    }

    func coreStorageClear(key: Data) throws {
        try withHostRejection {
            try bridge.coreStorage.clear(key: key)
            LiveSessionStoreForwarder.notifySessionStoreChanged()
        }
    }

    func chainConnect(genesisHash: Data) throws -> UInt32? {
        try withHostRejection {
            try bridge.chainConnect(genesisHash: genesisHash)
        }
    }

    func chainSend(connectionId: UInt32, request: String) throws {
        try withHostRejection {
            try bridge.chainSend(connectionId: connectionId, request: request)
        }
    }

    func chainClose(connectionId: UInt32) throws {
        try withHostRejection {
            try bridge.chainClose(connectionId: connectionId)
        }
    }

    func confirmUserAction(review: NativeUserConfirmationReview) async throws -> Bool {
        try await withHostRejection {
            try await bridge.confirmUserAction(review: review)
        }
    }

    func lookupPreimage(key: Data) async throws -> Data? {
        try await withHostRejection {
            try await bridge.lookupPreimage(key: key)
        }
    }

    func currentTheme() throws -> HostTheme {
        try withHostRejection {
            try bridge.currentTheme()
        }
    }

    func featureSupported(request: FeatureSupportedRequest) async throws -> Bool {
        try await withHostRejection {
            try await bridge.featureSupported(request: request)
        }
    }

    func localStorageRead(key: String) throws -> Data? {
        try withStorageError {
            try bridge.storage.read(key: key)
        }
    }

    func localStorageWrite(key: String, value: Data) throws {
        try withStorageError {
            try bridge.storage.write(key: key, value: value)
        }
    }

    func localStorageClear(key: String) throws {
        try withStorageError {
            try bridge.storage.clear(key: key)
        }
    }

    func chatSupported() -> Bool {
        bridge.supportsChat
    }

    func chatCreateRoom(
        roomId: String,
        name: String,
        icon: String
    ) throws -> NativeChatRoomRegistrationStatus {
        try withHostRejection {
            try bridge.chatCreateRoom(roomId: roomId, name: name, icon: icon)
        }
    }

    func chatPostTextMessage(roomId: String, text: String) throws -> String {
        try withHostRejection {
            try bridge.chatPostTextMessage(roomId: roomId, text: text)
        }
    }

    func chatPostCustomMessage(
        roomId: String,
        messageType: String,
        payload: Data
    ) throws -> String {
        try withHostRejection {
            try bridge.chatPostCustomMessage(
                roomId: roomId,
                messageType: messageType,
                payload: payload
            )
        }
    }

    func chatListRooms() throws -> [NativeChatRoom] {
        try withHostRejection { try bridge.chatListRooms() }
    }

    private func withHostRejection<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as HostRejection {
            throw error
        } catch {
            throw HostRejection.Rejected(reason: error.localizedDescription)
        }
    }

    private func withHostRejection<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as HostRejection {
            throw error
        } catch {
            throw HostRejection.Rejected(reason: error.localizedDescription)
        }
    }

    private func withNavigationRejection<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as HostNavigateRejection {
            throw error
        } catch {
            throw HostNavigateRejection.Unknown(reason: error.localizedDescription)
        }
    }

    private func withNavigationRejection<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as HostNavigateRejection {
            throw error
        } catch {
            throw HostNavigateRejection.Unknown(reason: error.localizedDescription)
        }
    }

    private func withStorageError<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as HostStorageError {
            throw error
        } catch {
            throw HostStorageError.Unknown(reason: error.localizedDescription)
        }
    }
}

/// Process-owned Rust host runtime. Product executables open independent
/// connections from this object and share its authentication and core services.
public final class TrUAPIHostRuntime: @unchecked Sendable {
    private let inner: NativeTrUApiHostRuntime
    private let callbackRetainer: HostCallbacks

    public init(bridge: HostBridge, runtimeConfig: HostRuntimeConfig) throws {
        let adapter = HostCallbackAdapter(bridge: bridge)
        callbackRetainer = adapter
        inner = try NativeTrUApiHostRuntime.withRuntimeConfig(
            callbacks: adapter,
            runtimeConfig: runtimeConfig.native
        )
        LiveSessionStoreForwarder.register(self)
        notifySessionStoreChanged()
    }

    deinit {
        LiveSessionStoreForwarder.unregister(self)
    }

    /// Open one executable connection with a host-assigned immutable context.
    public func openProductExecution(
        bridge: HostBridge,
        configuration: ProductExecutionConfig
    ) throws -> TrUAPIProductExecution {
        let adapter = HostCallbackAdapter(bridge: bridge)
        let execution = try inner.openProductExecution(
            callbacks: adapter,
            executionConfig: configuration.native
        )
        return TrUAPIProductExecution(inner: execution, callbackRetainer: adapter)
    }

    public func disconnect() {
        inner.disconnect()
    }

    public func notifySessionStoreChanged() {
        inner.notifySessionStoreChanged()
    }

    public func cancelLogin() {
        inner.cancelLogin()
    }

    public func activateLocalSession(secret: Data, liteUsername: String? = nil) throws {
        try inner.activateLocalSession(secret: secret, liteUsername: liteUsername)
    }

    public func notifyChainResponse(connectionId: UInt32, json: String) {
        inner.notifyChainResponse(connectionId: connectionId, json: json)
    }

    public func notifyChainClosed(connectionId: UInt32) {
        inner.notifyChainClosed(connectionId: connectionId)
    }
}

/// Testable surface for one connection-scoped product execution.
public protocol TrUAPIProductExecutionProtocol: AnyObject, Sendable {
    func startWsBridge(bindPort: UInt16) throws -> WsBridgeEndpoint
    func stopWsBridge()
    func close()
    func publishChatAction(_ action: NativeChatAction) throws
    func renderCustomMessage(
        messageId: String,
        messageType: String,
        payload: Data
    ) throws -> AsyncThrowingStream<NativeCustomRendererNode, Error>
    func permissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest
    ) throws -> NativePermissionAuthorizationStatus
    func setPermissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest,
        status: NativePermissionAuthorizationStatus
    ) throws
    func notifyThemeChanged(theme: HostTheme)
    func notifyPreimageChanged(key: Data, value: Data?)
    func notifyChainResponse(connectionId: UInt32, json: String)
    func notifyChainClosed(connectionId: UInt32)
    func notifyChatRoomsChanged(rooms: [NativeChatRoom])
}

/// One SPA or Chat executable connected to a shared host runtime.
public final class TrUAPIProductExecution: TrUAPIProductExecutionProtocol, @unchecked Sendable {
    private let inner: NativeProductExecution
    private let callbackRetainer: HostCallbacks

    fileprivate init(inner: NativeProductExecution, callbackRetainer: HostCallbacks) {
        self.inner = inner
        self.callbackRetainer = callbackRetainer
    }

    deinit {
        inner.shutdown()
    }

    public func startWsBridge(bindPort: UInt16 = 0) throws -> WsBridgeEndpoint {
        try inner.startWsBridge(bindPort: bindPort)
    }

    public func stopWsBridge() {
        inner.stopWsBridge()
    }

    public func close() {
        inner.shutdown()
    }

    public func publishChatAction(_ action: NativeChatAction) throws {
        try inner.publishChatAction(action: action)
    }

    public func renderCustomMessage(
        messageId: String,
        messageType: String,
        payload: Data
    ) throws -> AsyncThrowingStream<NativeCustomRendererNode, Error> {
        try customRendererStream { observer in
            try inner.renderCustomMessage(
                messageId: messageId,
                messageType: messageType,
                payload: payload,
                observer: observer
            )
        }
    }

    public func permissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest
    ) throws -> NativePermissionAuthorizationStatus {
        try inner.permissionAuthorizationStatus(request: request)
    }

    public func setPermissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest,
        status: NativePermissionAuthorizationStatus
    ) throws {
        try inner.setPermissionAuthorizationStatus(request: request, status: status)
    }

    public func notifyThemeChanged(theme: HostTheme) {
        inner.notifyThemeChanged(theme: theme)
    }

    public func notifyPreimageChanged(key: Data, value: Data?) {
        inner.notifyPreimageChanged(key: key, value: value)
    }

    public func notifyChainResponse(connectionId: UInt32, json: String) {
        inner.notifyChainResponse(connectionId: connectionId, json: json)
    }

    public func notifyChainClosed(connectionId: UInt32) {
        inner.notifyChainClosed(connectionId: connectionId)
    }

    public func notifyChatRoomsChanged(rooms: [NativeChatRoom]) {
        inner.notifyChatRoomsChanged(rooms: rooms)
    }
}

/// Owning wrapper around the Rust-backed `NativeTrUApiCore`. Holds the callback
/// bridge alive for the lifetime of the core and exposes session +
/// WS-bridge controls.
///
/// Hosts integrating with a `WKWebView`-based product call `startWsBridge`
/// and pass the resulting `ws://127.0.0.1:<port>/?t=<token>` URL to the
/// product via `LocalhostBridgeBootstrap.script(...)`. The product wires
/// that URL into `@parity/truapi`'s `createWebSocketProvider`.
public final class TrUAPIHostCore: TrUAPIHostCoreProtocol {
    let inner: NativeTrUApiCore

    // Rust holds the callback handle; this retainer pins the Swift side for
    // the core's lifetime.
    private let callbackRetainer: HostCallbacks

    /// Boot the Rust core against the host callbacks.
    public init(callbacks: HostCallbacks, runtimeConfig: RuntimeConfig) throws {
        callbackRetainer = callbacks
        inner = try NativeTrUApiCore.withRuntimeConfig(
            callbacks: callbacks,
            runtimeConfig: runtimeConfig.native
        )
        LiveSessionStoreForwarder.register(self)
        notifySessionStoreChanged()
    }

    deinit {
        LiveSessionStoreForwarder.unregister(self)
    }

    /// Start the localhost WebSocket bridge. Requires the `ws-bridge`
    /// feature in the cdylib. Pair the returned `WsBridgeEndpoint` with
    /// `LocalhostBridgeBootstrap.script(...)` to hand the URL to the
    /// product page.
    public func startWsBridge(bindPort: UInt16 = 0) throws -> WsBridgeEndpoint {
        try inner.startWsBridge(bindPort: bindPort)
    }

    /// Stop the localhost WebSocket bridge (if running).
    public func stopWsBridge() {
        inner.stopWsBridge()
    }

    /// Publish a native Chat action to this core's connected Chat worker.
    public func publishChatAction(_ action: NativeChatAction) throws {
        try inner.publishChatAction(action: action)
    }

    /// Stream typed replacement trees for one stored custom Chat message.
    public func renderCustomMessage(
        messageId: String,
        messageType: String,
        payload: Data
    ) throws -> AsyncThrowingStream<NativeCustomRendererNode, Error> {
        try customRendererStream { observer in
            try inner.renderCustomMessage(
                messageId: messageId,
                messageType: messageType,
                payload: payload,
                observer: observer
            )
        }
    }

    /// Core-owned logout/disconnect path. Best-effort notifies the SSO peer,
    /// clears in-memory session state, clears the persisted session via
    /// core storage, and broadcasts `Disconnected` to active
    /// account-status subscribers.
    public func disconnect() {
        inner.disconnect()
    }

    /// Notify the core after its host-private session storage changes.
    public func notifySessionStoreChanged() {
        inner.notifySessionStoreChanged()
    }

    /// Cancel an in-flight pairing login.
    ///
    /// Inert on a native host: the core is a signing host with no pairing flow
    /// to cancel, so calling this emits no auth state and changes nothing.
    public func cancelLogin() {
        inner.cancelLogin()
    }

    /// Activate or replace the local signing-host session from host-held raw
    /// BIP-39 entropy.
    public func activateLocalSession(secret: Data, liteUsername: String? = nil) throws {
        try inner.activateLocalSession(secret: secret, liteUsername: liteUsername)
    }

    /// Read a stored permission authorization status without prompting.
    public func permissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest
    ) throws -> NativePermissionAuthorizationStatus {
        try inner.permissionAuthorizationStatus(request: request)
    }

    /// Update a stored permission authorization status. `.notDetermined`
    /// clears the stored value so the next product request prompts again.
    public func setPermissionAuthorizationStatus(
        request: NativePermissionAuthorizationRequest,
        status: NativePermissionAuthorizationStatus
    ) throws {
        try inner.setPermissionAuthorizationStatus(request: request, status: status)
    }

    /// Push a host theme update to active TrUAPI theme subscriptions.
    public func notifyThemeChanged(theme: HostTheme) {
        inner.notifyThemeChanged(theme: theme)
    }

    /// Push a preimage lookup update to active subscriptions for `key`.
    public func notifyPreimageChanged(key: Data, value: Data?) {
        inner.notifyPreimageChanged(key: key, value: value)
    }

    /// Push a JSON-RPC response from a native chain connection into the core.
    public func notifyChainResponse(connectionId: UInt32, json: String) {
        inner.notifyChainResponse(connectionId: connectionId, json: json)
    }

    /// Notify the core that a native chain connection closed externally.
    public func notifyChainClosed(connectionId: UInt32) {
        inner.notifyChainClosed(connectionId: connectionId)
    }

    /// Push a complete replacement of the native Chat room list to active
    /// product subscriptions.
    public func notifyChatRoomsChanged(rooms: [NativeChatRoom]) {
        inner.notifyChatRoomsChanged(rooms: rooms)
    }
}
private func customRendererStream(
    _ subscribe: (CustomRendererStreamObserver) throws -> NativeCustomRendererSubscription
) throws -> AsyncThrowingStream<NativeCustomRendererNode, Error> {
    let (stream, continuation) = AsyncThrowingStream.makeStream(
        of: NativeCustomRendererNode.self
    )
    let observer = CustomRendererStreamObserver(continuation: continuation)
    let subscription = try subscribe(observer)
    continuation.onTermination = { @Sendable _ in
        subscription.cancel()
    }
    return stream
}

private final class CustomRendererStreamObserver: NativeCustomRendererObserver, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<NativeCustomRendererNode, Error>.Continuation

    init(continuation: AsyncThrowingStream<NativeCustomRendererNode, Error>.Continuation) {
        self.continuation = continuation
    }

    func onUpdate(node: NativeCustomRendererNode) {
        continuation.yield(node)
    }

    func onComplete() {
        continuation.finish()
    }
}

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

private enum LiveSessionStoreForwarder {
    private static let lock = NSLock()
    private static var cores: [ObjectIdentifier: WeakReference<TrUAPIHostCore>] = [:]
    private static var runtimes: [ObjectIdentifier: WeakReference<TrUAPIHostRuntime>] = [:]

    static func register(_ runtime: TrUAPIHostRuntime) {
        lock.lock()
        runtimes[ObjectIdentifier(runtime)] = WeakReference(runtime)
        lock.unlock()
    }

    static func unregister(_ runtime: TrUAPIHostRuntime) {
        lock.lock()
        runtimes.removeValue(forKey: ObjectIdentifier(runtime))
        lock.unlock()
    }

    static func register(_ core: TrUAPIHostCore) {
        lock.lock()
        cores[ObjectIdentifier(core)] = WeakReference(core)
        lock.unlock()
    }

    static func unregister(_ core: TrUAPIHostCore) {
        lock.lock()
        cores.removeValue(forKey: ObjectIdentifier(core))
        lock.unlock()
    }

    static func notifySessionStoreChanged() {
        let liveCores: [TrUAPIHostCore]
        let liveRuntimes: [TrUAPIHostRuntime]

        lock.lock()
        cores = cores.filter { $0.value.value != nil }
        runtimes = runtimes.filter { $0.value.value != nil }
        liveCores = cores.values.compactMap(\.value)
        liveRuntimes = runtimes.values.compactMap(\.value)
        lock.unlock()

        for core in liveCores {
            core.notifySessionStoreChanged()
        }
        for runtime in liveRuntimes {
            runtime.notifySessionStoreChanged()
        }
    }
}
