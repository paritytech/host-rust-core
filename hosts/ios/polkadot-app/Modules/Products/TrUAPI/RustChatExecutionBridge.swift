import Foundation
import FoundationExt
import Products
import TrUAPIHost

/// Per-execution bridge for the native Chat modality: a
/// ``RustProductExecutionBridge`` that also answers the rust core's
/// `ChatHostBridge` callbacks against the product's chat binding.
///
/// `ChatHostBridge` is synchronous and the surface is async, so calls block on a
/// detached task.
final class RustChatExecutionBridge: RustProductExecutionBridge, ChatHostBridge, @unchecked Sendable {
    private let chatMessaging: any ProductChatMessaging
    // The base class keeps `dependencies` private; hold on to the logger here.
    private let logger: LoggerProtocol
    /// How long a callback waits for the surface. Injectable so a test is not racing
    /// a wall clock: under a loaded test bundle a task can wait seconds for a core.
    private let callTimeout: DispatchTimeInterval

    init(
        dependencies: Dependencies,
        chatMessaging: any ProductChatMessaging,
        callTimeout: DispatchTimeInterval = .seconds(2)
    ) {
        self.chatMessaging = chatMessaging
        self.callTimeout = callTimeout
        logger = dependencies.logger
        super.init(dependencies: dependencies)
    }

    func createRoom(roomId: String, name: String, icon: String) throws -> ChatRoomRegistrationStatus {
        logger.debug("[truapi:chat-bridge] createRoom \(roomId)")
        let api = chatMessaging
        let result = try awaitBlocking {
            try await api.createRoom(CreateRoomRequest(
                roomId: roomId,
                name: name.nilIfEmpty,
                icon: icon.nilIfEmpty
            ))
        }
        return switch result.status {
        case .new: .new
        case .exists: .exists
        }
    }

    func registerBot(botId: String, name _: String, icon _: String) throws -> ChatBotRegistrationStatus {
        logger.debug("[truapi:chat-bridge] registerBot \(botId) -> rejecting")
        // No native bot registry; the container leaves it unimplemented too.
        throw HostRejection.Rejected(reason: "bot registration is not supported by this host")
    }

    func postMessage(roomId: String, content: ChatMessageContent) throws -> String {
        // Message bodies are user content and this logger has a file destination
        // on testnet builds: log the variant, never the payload.
        logger.debug("[truapi:chat-bridge] postMessage \(roomId) \(content.variantName)")
        // This bridge validates product input whatever the core does upstream: a
        // roomless body lands in the bot's default chat, which no `RenderContext`
        // can name and so no renderer could ever draw.
        guard let roomId = roomId.nilIfEmpty else {
            throw HostRejection.Rejected(reason: "a chat message needs a room")
        }

        let api = chatMessaging
        let message: ProductBotMessage = switch content {
        case let .text(text):
            .text(text)
        case let .custom(custom):
            .custom(messageType: custom.messageType, data: custom.payload)
        case .richText, .actions, .file, .reaction, .reactionRemoved:
            throw HostRejection.Rejected(reason: "this host renders text and custom messages only")
        }
        return try awaitBlocking {
            try await api.sendMessage(message, roomId: roomId)
        }
    }

    func listRooms() throws -> [ChatRoom] {
        logger.debug("[truapi:chat-bridge] listRooms")
        let api = chatMessaging
        // An empty result matches what the core publishes on failure anyway
        // (`list_rooms().unwrap_or_default()`).
        let rooms = try awaitBlocking { () -> [RoomInfo] in
            for try await rooms in try await api.subscribeRooms() {
                return rooms
            }
            return []
        }
        return rooms.map { $0.toChatRoom() }
    }
}

extension RoomInfo {
    func toChatRoom() -> ChatRoom {
        let participatingAs: ChatRoomParticipation = switch participation {
        case .roomHost: .roomHost
        case .bot: .bot
        }
        return ChatRoom(roomId: roomId, participatingAs: participatingAs)
    }
}

private extension RustChatExecutionBridge {
    /// Blocks a core dispatch thread shared by every execution, so waits are bounded
    /// and short — `create_chat_room` calls back twice in a row.
    func awaitBlocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
        let timeout = callTimeout
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<T, Error> = .failure(CancellationError())
        let task = Task.detached(priority: .userInitiated) {
            do {
                outcome = .success(try await body())
            } catch {
                outcome = .failure(error)
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            // Cancellation misses an in-flight save, so a message may still land
            // without the product ever getting its id.
            task.cancel()
            logger.error("[truapi:chat-bridge] timed out waiting on the native api; the call may still complete")
            throw HostRejection.Rejected(
                reason: "the host did not answer in time; a message send may still have been applied"
            )
        }
        return try outcome.get()
    }
}

private extension ChatMessageContent {
    var variantName: String {
        switch self {
        case .text: "text"
        case .richText: "richText"
        case .custom: "custom"
        case .actions: "actions"
        case .file: "file"
        case .reaction: "reaction"
        case .reactionRemoved: "reactionRemoved"
        }
    }
}
