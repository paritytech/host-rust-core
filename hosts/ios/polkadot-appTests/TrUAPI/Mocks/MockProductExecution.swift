import Foundation
import TrUAPIHost

/// Test double for one product execution. Records ws-bridge lifecycle and
/// chain notify-backs; unused notify surfaces are inert.
final class MockProductExecution: TrUAPIProductExecutionProtocol, @unchecked Sendable {
    private(set) var startWsBridgeCallCount = 0
    private(set) var stopWsBridgeCallCount = 0
    private(set) var closeCallCount = 0
    private(set) var chainResponses: [(UInt32, String)] = []
    private(set) var chainClosed: [UInt32] = []

    /// Status returned by `permissionAuthorizationStatus`; defaults to
    /// `.notDetermined` so existing tests are unaffected.
    var permissionStatus: PermissionAuthorizationStatus = .notDetermined
    private(set) var permissionRequests: [PermissionAuthorizationRequest] = []

    func startWsBridge(bindPort _: UInt16) throws -> WsBridgeEndpoint {
        startWsBridgeCallCount += 1
        return WsBridgeEndpoint(port: 0, token: "test")
    }

    func stopWsBridge() {
        stopWsBridgeCallCount += 1
    }

    func close() {
        closeCallCount += 1
    }

    func publishChatAction(_: HostChatActionSubscribeItem) throws {}

    func renderCustomMessage(
        messageId _: String,
        messageType _: String,
        payload _: Data
    ) throws -> AsyncThrowingStream<CustomRendererNode, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func permissionAuthorizationStatus(
        request: PermissionAuthorizationRequest
    ) async throws -> PermissionAuthorizationStatus {
        permissionRequests.append(request)
        return permissionStatus
    }

    func setPermissionAuthorizationStatus(
        request _: PermissionAuthorizationRequest,
        status _: PermissionAuthorizationStatus
    ) throws {}

    func notifyThemeChanged(theme _: HostThemeSubscribeItem) {}
    func notifyLocaleChanged(locale _: HostLocaleSubscribeItem) {}
    func notifyPreimageChanged(key _: Data, value _: Data?) {}

    func notifyChainResponse(connectionId: UInt32, json: String) {
        chainResponses.append((connectionId, json))
    }

    func notifyChainClosed(connectionId: UInt32) {
        chainClosed.append(connectionId)
    }

    func notifyChatRoomsChanged(rooms _: [ChatRoom]) {}

    func sessionChatIdentityKey() throws -> Data? {
        nil
    }
}
