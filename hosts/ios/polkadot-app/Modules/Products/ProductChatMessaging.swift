import Foundation
import os
import Products
import AsyncExtensions

/// The chat calls a product's bot can make. All the rust chat bridge needs from
/// the native surface: `ChatHostBridge`'s fourth callback, `registerBot`, is
/// rejected outright.
protocol ProductChatMessaging: Sendable {
    func sendMessage(_ message: ProductBotMessage, roomId: String?) async throws -> String
    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResult
    func subscribeRooms() async throws -> AnyAsyncSequence<[RoomInfo]>
}

/// Serves those calls from a chat binding. Conformers differ only in where the
/// binding lives — the shared worker's native api holds one for its whole
/// lifetime, the rust runtime holds its own.
protocol BoundProductChatMessaging: ProductChatMessaging {
    var currentMessaging: ProductsNativeApi.MessagingSupport? { get }

    /// Pacing applied before the write. The shared worker keeps the native bot's
    /// typing affordance; the rust path opts out because its callbacks are
    /// synchronous and hold a core dispatch thread for the whole delay.
    var messageDeliveryDelay: MessageDeliveryDelay { get }
}

extension BoundProductChatMessaging {
    var messageDeliveryDelay: MessageDeliveryDelay { .humanInteraction }

    func sendMessage(_ message: ProductBotMessage, roomId: String?) async throws -> String {
        let (context, bot) = try requireMessaging()
        let content = message.toChatMessageContent()

        let chatMessage: Chat.LocalMessage =
            if let roomId {
                try await context.sendNewMessage(
                    from: bot,
                    roomId: roomId,
                    newContent: content,
                    messageDeliveryDelay: messageDeliveryDelay
                )
            } else {
                try await context.sendNewMessage(
                    from: bot,
                    newContent: content,
                    messageDeliveryDelay: messageDeliveryDelay
                )
            }

        return chatMessage.messageId
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResult {
        let (context, bot) = try requireMessaging()

        let status = try await context.createRoom(
            for: bot,
            roomId: request.roomId,
            name: request.name,
            icon: request.icon
        )

        return CreateRoomResult(status: status)
    }

    func subscribeRooms() async throws -> AnyAsyncSequence<[RoomInfo]> {
        let (context, bot) = try requireMessaging()
        return await context.subscribeRooms(for: bot)
    }
}

private extension BoundProductChatMessaging {
    /// One read of the binding, so a rebind cannot tear the `context`/`bot` pair
    /// across two separate reads.
    func requireMessaging() throws -> (ChatExtensionDiscoverContextProtocol, any ChatExtensionBotProtocol) {
        let messaging = currentMessaging
        guard let context = messaging?.context else { throw ProductNativeApiError.messagesNotSupported }
        guard let bot = messaging?.bot else { throw ProductNativeApiError.chatBotMissing }
        return (context, bot)
    }
}

/// Holds the chat binding for a runtime that serves the core directly instead
/// of going through the shared worker's native api. Bound while the chat
/// surface is alive and cleared on dispose, matching
/// ``ProductsNativeApi/bindMessaging(_:)``.
final class ProductChatSurface: BoundProductChatMessaging, @unchecked Sendable {
    let messageDeliveryDelay: MessageDeliveryDelay = .immediate

    private let messaging = OSAllocatedUnfairLock<ProductsNativeApi.MessagingSupport?>(initialState: nil)

    var currentMessaging: ProductsNativeApi.MessagingSupport? {
        messaging.withLock { $0 }
    }

    func bind(_ support: ProductsNativeApi.MessagingSupport) {
        messaging.withLock { $0 = support }
    }

    func unbind() {
        messaging.withLock { $0 = nil }
    }
}
