import Foundation
import TrUAPIHost

/// Per-execution bridge for the native Chat modality: a
/// ``RustProductExecutionBridge`` that also answers the rust core's
/// `ChatHostBridge` callbacks. The native chat surface is not wired yet, so
/// these stubs trap in debug and reject the core call in release until the
/// chat integration lands.
final class RustChatExecutionBridge: RustProductExecutionBridge, ChatHostBridge, @unchecked Sendable {
    func registerBot(botId _: String, name _: String, icon _: String) throws -> ChatBotRegistrationStatus {
        throw notImplemented(#function)
    }

    func createRoom(roomId _: String, name _: String, icon _: String) throws -> ChatRoomRegistrationStatus {
        throw notImplemented(#function)
    }

    func postMessage(roomId _: String, content _: ChatMessageContent) throws -> String {
        throw notImplemented(#function)
    }

    func listRooms() throws -> [ChatRoom] {
        throw notImplemented(#function)
    }
}

private extension RustChatExecutionBridge {
    func notImplemented(_ function: String) -> HostRejection {
        assertionFailure("RustChatExecutionBridge.\(function) is not implemented yet")
        return HostRejection.Rejected(reason: "chat host bridge not implemented")
    }
}
