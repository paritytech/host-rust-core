import Foundation
import Foundation_iOS
import SubstrateSdk
import PolkadotUI
import SwiftUI
import ChainRegistry

final class GameDepositMessageDecoder {
    let identifier = MessageDecoderIdentifier.gameDeposit

    let chain: ChainModel

    init(chain: ChainModel) {
        self.chain = chain
    }
}

extension GameDepositMessageDecoder: ChatMessageCustomDecoding {
    func decode(data: Data, context _: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        do {
            let decoder = try ScaleDecoder(data: data)
            let result = try Deposit(scaleDecoder: decoder)

            guard let asset = chain.asset(for: result.assetId) else { return [] }

            let assetInfo = asset.displayInfo

            let amountText = AssetBalanceFormatterFactory()
                .createTokenFormatter(for: assetInfo)
                .value(for: .current)
                .stringFromDecimal(result.amount.decimal(assetInfo: assetInfo))

            guard let amountText else { return [] }

            return [ChatSystemMessageConfiguration.deposit(amount: amountText)]
        } catch {
            return []
        }
    }

    func previewString(data: Data) -> String {
        guard let decoder = try? ScaleDecoder(data: data),
              let result = try? Deposit(scaleDecoder: decoder),
              let asset = chain.asset(for: result.assetId)
        else { return "" }

        let assetInfo = asset.displayInfo

        let amountText = AssetBalanceFormatterFactory()
            .createTokenFormatter(for: assetInfo)
            .value(for: .current)
            .stringFromDecimal(result.amount.decimal(assetInfo: assetInfo))

        guard let amountText else { return "" }

        return String(localized: .chatDepositAdded(amount: amountText))
    }
}

// MARK: - Content

extension GameDepositMessageDecoder {
    struct Deposit: ScaleCodable {
        let amount: Balance
        let assetId: AssetId

        var identifier: String {
            [
                "deposit-added",
                "\(amount.toHexString())",
                "\(assetId)"
            ].joined(with: .dash)
        }

        init(
            amount: Balance,
            assetId: AssetId
        ) {
            self.amount = amount
            self.assetId = assetId
        }

        init(scaleDecoder: any ScaleDecoding) throws {
            amount = try Balance(scaleDecoder: scaleDecoder)
            assetId = try AssetId(scaleDecoder: scaleDecoder)
        }

        func encode(scaleEncoder: any ScaleEncoding) throws {
            try amount.encode(scaleEncoder: scaleEncoder)
            try assetId.encode(scaleEncoder: scaleEncoder)
        }
    }
}
