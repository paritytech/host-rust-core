import Foundation
import AsyncExtensions
import SubstrateSdk

actor GameResultProcessingContext {
    private let context: ChatExtensionDiscoverContextProtocol
    private let logger: LoggerProtocol

    init(context: ChatExtensionDiscoverContextProtocol, logger: LoggerProtocol) {
        self.context = context
        self.logger = logger
    }

    func process(
        results: AnyAsyncSequence<[GameResultsMessageDecoder.GameResult]>,
        sender: ChatExtensionBotProtocol
    ) async throws {
        for try await result in results {
            try Task.checkCancellation()

            logger.debug("Processing game results")

            async let messages = try context.getMessages(of: .customRendered)
            let keyedMessages: [String: Chat.LocalMessage] = try await messages.reduce(into: [:]) {
                guard let key = $1.content.contentKey else {
                    return
                }
                $0[key] = $1
            }

            for gameResult in result {
                let content: Chat.LocalMessage.Content = try .customRendered(
                    .init(
                        decoderId: MessageDecoderIdentifier.gameResults.rawValue,
                        data: gameResult.scaleEncoded(),
                        identifier: gameResult.identifier
                    )
                )

                guard let message = keyedMessages[gameResult.identifier] else {
                    logger.debug("Saving new game message...")

                    try await context.sendNewMessage(
                        from: sender,
                        newContent: content,
                        messageDeliveryDelay: .immediate
                    )

                    logger.debug("New game message saved")
                    continue
                }

                guard
                    !message.isFinalizedGameResult,
                    message.content != content
                else {
                    continue
                }

                logger.debug("Modifying game message...")

                // Modify not finalized local game results only
                try await context.modifyMessageContent(
                    messageId: message.messageId,
                    content: content
                )

                logger.debug("Game message modified")
            }
        }
    }
}

private extension Chat.LocalMessage {
    var isFinalizedGameResult: Bool {
        guard
            case let .customRendered(content) = content
        else {
            return true
        }
        do {
            let decoder = try ScaleDecoder(data: content.data)
            let state = try GameResultsMessageDecoder.GameResult(scaleDecoder: decoder).state

            return state != .pending
        } catch {
            return true
        }
    }
}
