import Foundation
import Products
import AsyncExtensions

// MARK: - Messaging

extension ProductsNativeApi {
    func sendMessage(_ message: ProductBotMessage, roomId: String?) async throws -> String {
        let messaging = currentMessaging
        guard let context = messaging?.context else { throw ProductNativeApiError.messagesNotSupported }
        guard let bot = messaging?.bot else { throw ProductNativeApiError.chatBotMissing }

        let content = message.toChatMessageContent()

        let chatMessage: Chat.LocalMessage =
            if let roomId {
                try await context.sendNewMessage(
                    from: bot,
                    roomId: roomId,
                    newContent: content,
                    messageDeliveryDelay: .humanInteraction
                )
            } else {
                try await context.sendNewMessage(
                    from: bot,
                    newContent: content,
                    messageDeliveryDelay: .humanInteraction
                )
            }

        return chatMessage.messageId
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResult {
        let messaging = currentMessaging
        guard let context = messaging?.context else { throw ProductNativeApiError.messagesNotSupported }
        guard let bot = messaging?.bot else { throw ProductNativeApiError.chatBotMissing }

        let status = try await context.createRoom(
            for: bot,
            roomId: request.roomId,
            name: request.name,
            icon: request.icon
        )

        return CreateRoomResult(status: status)
    }

    func subscribeRooms() async throws -> AnyAsyncSequence<[RoomInfo]> {
        let messaging = currentMessaging
        guard let context = messaging?.context else { throw ProductNativeApiError.messagesNotSupported }
        guard let bot = messaging?.bot else { throw ProductNativeApiError.chatBotMissing }

        return await context.subscribeRooms(for: bot)
    }
}

// MARK: - Helpers

extension ProductBotMessage {
    func toChatMessageContent() -> Chat.LocalMessage.Content {
        switch self {
        case let .text(text):
            .text(text)
        case let .custom(messageType, data):
            .customRendered(
                Chat.LocalMessage.Content.CustomRenderedData(
                    decoderId: MessageDecoderIdentifier.product.rawValue,
                    data: data,
                    identifier: messageType
                )
            )
        }
    }
}
