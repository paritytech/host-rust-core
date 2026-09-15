import Foundation
import SubstrateSdk
import Operation_iOS
import Coinage

protocol LocalMessageCreatingOperationMaking {
    func createTransfer(
        to chatId: Chat.Id,
        memo: TransferMemo,
        messageId: Chat.MessageId
    ) -> BaseOperation<Void>

    func createReplyMessageOperation(
        to chatId: Chat.Id,
        text: String,
        replyToMessageId: String
    ) -> BaseOperation<Void>

    func send(content: Chat.LocalMessage.Content, to chatId: Chat.Id) async throws
}

final class LocalMessageCreatingOperationFactory: LocalMessageCreatingOperationMaking {
    private let messagesStorageService: MessagesLocalStorageServicing

    init(messagesStorageService: MessagesLocalStorageServicing = MessagesLocalStorageService()) {
        self.messagesStorageService = messagesStorageService
    }

    func createTransfer(
        to chatId: Chat.Id,
        memo: TransferMemo,
        messageId: Chat.MessageId
    ) -> BaseOperation<Void> {
        let content = Chat.LocalMessage.Content.Transfer(
            totalValue: memo.totalValue,
            coinKeys: memo.entries,
            status: nil
        )

        let local = Chat.LocalMessage.newMessage(
            to: chatId,
            content: .coinageSend(content),
            messageId: messageId
        )

        return messagesStorageService.insertOrUpdate([local])
    }

    func createReplyMessageOperation(
        to chatId: Chat.Id,
        text: String,
        replyToMessageId: String
    ) -> BaseOperation<Void> {
        let richTextContent = ChatRemoteMessageContent.RichText(
            text: text,
            attachments: nil
        )
        let content = Chat.RemoteMessageContentV1.MessageContent.ReplyContent(
            messageId: replyToMessageId,
            ownContent: richTextContent
        )

        let local = Chat.LocalMessage.newMessage(
            to: chatId,
            content: .reply(content)
        )

        return messagesStorageService.insertOrUpdate([local])
    }

    func send(content: Chat.LocalMessage.Content, to chatId: Chat.Id) async throws {
        let status: Chat.LocalMessage.Status =
            switch chatId {
            case .person: .outgoing(.new)
            case .chatExtension: .outgoing(.delivered)
            }

        let newMessage = Chat.LocalMessage
            .newMessage(to: chatId, content: content)
            .replacingStatus(status)

        try await messagesStorageService
            .insertOrUpdate([newMessage])
            .asyncExecute()
    }
}
