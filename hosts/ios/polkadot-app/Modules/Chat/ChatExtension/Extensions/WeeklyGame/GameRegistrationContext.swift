import Foundation
import AsyncExtensions
import SubstrateSdk

actor GameRegistrationContext {
    private let context: ChatExtensionDiscoverContextProtocol

    init(context: ChatExtensionDiscoverContextProtocol) {
        self.context = context
    }
}

extension GameRegistrationContext {
    func process(
        results: AnyAsyncSequence<GameInfo>,
        sender: ChatExtensionBotProtocol
    ) async throws {
        for try await gameInfo in results {
            try Task.checkCancellation()
            guard let gameDate = gameInfo.gameDate else { continue }

            let info = GameRegistrationMessageDecoder.Content(
                gameIndex: gameInfo.index,
                gameDate: gameDate
            )

            let content: Chat.LocalMessage.Content = try .customRendered(
                .init(
                    decoderId: MessageDecoderIdentifier.gameRegistration.rawValue,
                    data: info.scaleEncoded(),
                    identifier: info.identifier
                )
            )

            _ = try await context.sendNewMessage(
                from: sender,
                newContent: content,
                messageDeliveryDelay: .immediate
            )
        }
    }
}
