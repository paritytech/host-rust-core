import Foundation
import AsyncExtensions
import SubstrateSdk
import Individuality

actor PersonhoodRegisteredContext {
    private let context: ChatExtensionDiscoverContextProtocol

    init(context: ChatExtensionDiscoverContextProtocol) {
        self.context = context
    }
}

extension PersonhoodRegisteredContext {
    func process(
        sequence: AnyAsyncSequence<PeoplePallet.PersonalId>,
        sender: ChatExtensionBotProtocol
    ) async throws {
        for try await personalId in sequence {
            try Task.checkCancellation()

            let content = PersonhoodRegisteredMessageDecoder.Content(personalId: personalId)

            let messages = try await context.getMessagesByContentKey(content.identifier, with: sender)

            guard messages.isEmpty else {
                continue
            }

            let messageContent: Chat.LocalMessage.Content = try .customRendered(
                .init(
                    decoderId: MessageDecoderIdentifier.personhoodRegistered.rawValue,
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
