import Foundation
import AsyncExtensions
import SubstrateSdk

actor FullUsernameClaimedContext {
    private let context: ChatExtensionDiscoverContextProtocol

    init(context: ChatExtensionDiscoverContextProtocol) {
        self.context = context
    }
}

extension FullUsernameClaimedContext {
    func process(
        contentSequence: AnyAsyncSequence<FullUsernameClaimedMessageDecoder.Content>,
        sender: ChatExtensionBotProtocol
    ) async throws {
        for try await content in contentSequence {
            try Task.checkCancellation()

            let messages = try await context.getMessagesByContentKey(content.identifier, with: sender)

            guard messages.isEmpty else {
                continue
            }

            let messageContent: Chat.LocalMessage.Content = try .customRendered(
                .init(
                    decoderId: MessageDecoderIdentifier.fullUsernameClaimed.rawValue,
                    data: content.scaleEncoded(),
                    identifier: content.identifier
                )
            )

            _ = try await context.sendNewMessage(
                from: sender,
                newContent: messageContent,
                messageDeliveryDelay: .immediate
            )
        }
    }
}
