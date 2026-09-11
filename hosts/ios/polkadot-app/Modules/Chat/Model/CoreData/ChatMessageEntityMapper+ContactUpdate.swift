import Foundation
import CoreData
import SubstrateSdk

extension ChatMessageEntityMapper {
    func updateChatBasedOnNewMessage(
        chatEntity: CDChat,
        message: Chat.LocalMessage,
        messageState: MessageState,
        messageEntity: CDChatMessage,
        context: NSManagedObjectContext
    ) throws {
        updateLastMessage(
            message: message,
            messageState: messageState,
            messageEntity: messageEntity,
            chatEntity: chatEntity
        )

        try updateMessageStatus(
            messageEntity: messageEntity,
            message: message,
            context: context
        )
    }
}

private extension ChatMessageEntityMapper {
    func updateLastMessage(
        message: Chat.LocalMessage,
        messageState: MessageState,
        messageEntity: CDChatMessage,
        chatEntity: CDChat
    ) {
        // system messages, reactions and edits shouldn't update lastDisplayMessage
        guard messageState.isNew, !message.isExcludedFromChatList else {
            return
        }

        guard let lastMessage = chatEntity.lastDisplayMessage else {
            chatEntity.lastDisplayMessage = messageEntity
            return
        }

        guard lastMessage.messageId != message.messageId else {
            return
        }

        let lastTimestamp = UInt64(bitPattern: lastMessage.timestamp)

        guard lastTimestamp <= message.timestamp else {
            return
        }

        lastMessage.lastDisplayMessageChat = nil
        chatEntity.lastDisplayMessage = messageEntity
    }

    func updateMessageStatus(
        messageEntity: CDChatMessage,
        message: Chat.LocalMessage,
        context: NSManagedObjectContext
    ) throws {
        let update = Chat.ChatMessageStatusUpdate(messageId: message.messageId, status: message.status)
        let updateMapper = ChatMessageStatusUpdateMapper()
        try updateMapper.populate(entity: messageEntity, from: update, using: context)
    }
}
