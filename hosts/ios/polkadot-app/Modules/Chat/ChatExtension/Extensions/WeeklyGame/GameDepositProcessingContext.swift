import Foundation
import AsyncExtensions
import SubstrateSdk

actor GameDepositProcessingContext {
    private let context: ChatExtensionDiscoverContextProtocol

    init(context: ChatExtensionDiscoverContextProtocol) {
        self.context = context
    }
}

extension GameDepositProcessingContext {
    func process(
        deposit: ConfirmedDeposit,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let model = GameDepositMessageDecoder.Deposit(
            amount: deposit.amount,
            assetId: deposit.chainAssetId.assetId
        )

        let content: Chat.LocalMessage.Content = try .customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.gameDeposit.rawValue,
                data: model.scaleEncoded(),
                identifier: model.identifier
            )
        )

        try await context.sendNewMessage(
            from: sender,
            newContent: content,
            messageDeliveryDelay: .immediate
        )
    }
}
