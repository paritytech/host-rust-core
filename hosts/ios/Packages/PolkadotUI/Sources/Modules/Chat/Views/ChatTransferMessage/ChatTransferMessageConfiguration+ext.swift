import Foundation
import UIKit

public extension ChatTransferMessageConfiguration {
    static func inbox(
        amount: String,
        tokenSymbol: String,
        originalAmount: String? = nil,
        from username: String,
        state: ChatTransferMessageConfiguration.State,
        statusConfiguration: ChatMessageStatusViewConfiguration,
        addReaction: ChatMessageContainerConfiguration.AddReactionViewModel? = nil,
        messageReaction: ChatMessageContainerConfiguration.MessageReactionViewModel? = nil
    ) -> ChatMessageContainerConfiguration {
        let configuration = ChatTransferMessageConfiguration(
            title: state.inboxTitle(username: username),
            amountText: amount,
            tokenSymbol: tokenSymbol,
            originalAmountText: originalAmount,
            state: .incoming(state),
            statusConfiguration: statusConfiguration,
            backgroundColor: .bgSurfaceContainer,
            titleColor: .fgPrimary,
            amountBackgroundColor: .bgSurfaceNested,
            amountTextColor: .fgPrimary,
            originalAmountTextColor: .fgSecondary,
            side: .leading
        )

        return ChatMessageContainerConfiguration(
            innerContent: configuration,
            side: .leading,
            bubbleColor: .clear,
            addReaction: addReaction,
            messageReaction: messageReaction,
            contentInsets: .zero,
            identifier: ChatTransferMessageConfiguration.defaultReuseIdentifier
        )
    }

    static func outbox(
        amount: String,
        tokenSymbol: String,
        originalAmount: String? = nil,
        state: ChatTransferMessageConfiguration.State,
        statusConfiguration: ChatMessageStatusViewConfiguration,
        addReaction: ChatMessageContainerConfiguration.AddReactionViewModel? = nil,
        messageReaction: ChatMessageContainerConfiguration.MessageReactionViewModel? = nil
    ) -> ChatMessageContainerConfiguration {
        let configuration = ChatTransferMessageConfiguration(
            title: String(localized: .chatTransferOutbox),
            amountText: amount,
            tokenSymbol: tokenSymbol,
            originalAmountText: originalAmount,
            state: .outgoing(state),
            statusConfiguration: statusConfiguration,
            backgroundColor: .bgSurfaceContainerInverted,
            titleColor: .fgPrimaryInverted,
            amountBackgroundColor: .bgSurfaceNestedInverted,
            amountTextColor: .fgPrimaryInverted,
            originalAmountTextColor: .fgSecondaryInverted,
            side: .trailing
        )

        return ChatMessageContainerConfiguration(
            innerContent: configuration,
            side: .trailing,
            bubbleColor: .clear,
            addReaction: addReaction,
            messageReaction: messageReaction,
            contentInsets: .zero,
            identifier: ChatTransferMessageConfiguration.defaultReuseIdentifier
        )
    }
}

private extension ChatTransferMessageConfiguration.State {
    func inboxTitle(username: String) -> String {
        switch self {
        case .finished,
             .sent,
             .partiallyClaimed,
             .error:
            String(localized: .chatTransferInbox(username: username))
        case .processing,
             .claiming:
            String(localized: .chatTransferInboxSending(username: username))
        }
    }
}
