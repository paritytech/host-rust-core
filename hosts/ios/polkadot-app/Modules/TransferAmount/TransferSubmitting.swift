import Coinage
import Foundation
import Operation_iOS
import StructuredConcurrency
import SubstrateSdk
import SDKLogger

protocol TransferSubmitting {
    /// When `true`, the interactor propagates `sendChatMessage` errors instead
    /// of swallowing them. Default `false` matches best-effort chat-memo delivery.
    var isFailureFatal: Bool { get }

    /// `messageId` is the id the caller pre-generated for this transfer, used both as the coinage
    /// transactions' groupId and as the id of the chat message that carries the memo.
    func sendTransfer(_ memo: TransferMemo, to recipient: AccountId, messageId: Chat.MessageId) async throws
}

extension TransferSubmitting {
    var isFailureFatal: Bool { false }
}

final class ContactChatSubmitter: TransferSubmitting {
    private let chatContactsProvider: ContactsLocalStorageServicing
    private let createMessageFactory: LocalMessageCreatingOperationMaking
    private let logger: SDKLoggerProtocol?

    init(
        chatContactsProvider: ContactsLocalStorageServicing,
        createMessageFactory: LocalMessageCreatingOperationMaking,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.chatContactsProvider = chatContactsProvider
        self.createMessageFactory = createMessageFactory
        self.logger = logger
    }

    func sendTransfer(_ memo: TransferMemo, to recipient: AccountId, messageId: Chat.MessageId) async throws {
        let optContact = try await chatContactsProvider.getContact(by: recipient).asyncExecute()

        guard let contact = optContact.flatMap({ $0 }) else {
            logger?.debug("No chat contact found within timeout — skipping message")
            return
        }

        let operation = createMessageFactory.createTransfer(
            to: Chat.Id.person(contact.accountId),
            memo: memo,
            messageId: messageId
        )
        try await CompoundOperationWrapper(targetOperation: operation).asyncExecute()
    }
}

struct NoChatSubmitter: TransferSubmitting {
    func sendTransfer(_: TransferMemo, to _: AccountId, messageId _: Chat.MessageId) async throws {}
}
