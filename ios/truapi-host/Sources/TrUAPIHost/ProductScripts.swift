// User-script installation for a product web view.
//
// The lockdown container's guarantees depend on two things a host would
// otherwise have to get right by hand, so the package owns both.

#if canImport(WebKit)

import WebKit

public extension TrUAPIHost {
    /// Registers the bootstrap and lockdown container on `controller` with the
    /// frame scopes the lockdown depends on, resolving the container's policy
    /// from `core`.
    ///
    /// Prefer this over registering the scripts by hand. Two properties are
    /// easy to get wrong and silently fatal:
    ///
    /// - **The container must run in every frame.** A frame without it has
    ///   pristine `fetch`, `WebSocket`, `XMLHttpRequest` and
    ///   `RTCPeerConnection`, and a product reaches one through an `<iframe>` in
    ///   its own HTML — parsed before any script runs — so intercepting DOM
    ///   creation APIs is no substitute. The bootstrap stays main-frame-only:
    ///   a subframe then has no bridge endpoint and no policy, and every gate in
    ///   the container fails closed there.
    /// - **The WebRTC decision is a peek, never a prompt**, and it is baked in
    ///   as a literal because the container enforces it inside the product's own
    ///   realm, where an asynchronous permission request would be forgeable. A
    ///   fresh grant therefore only applies once the web view reloads.
    ///
    /// Call before the web view loads the product page.
    static func installProductScripts(
        into controller: WKUserContentController,
        core: any TrUAPIHostCoreProtocol,
        endpoint: WsBridgeEndpoint
    ) async throws {
        let webRtcAllowed = try await core.permissionAuthorizationStatus(
            request: .remote(RemotePermissionRequest(permission: .webRtc))
        ) == .authorized

        controller.addUserScript(WKUserScript(
            source: LocalhostBridgeBootstrap.script(
                port: endpoint.port,
                token: endpoint.token,
                webRtcAllowed: webRtcAllowed
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: try ContainerScriptBundle.load(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
    }
}

#endif
