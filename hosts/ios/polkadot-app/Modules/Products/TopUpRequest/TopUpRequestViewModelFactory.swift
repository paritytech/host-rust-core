import Foundation
import Products
import SubstrateSdk
import ChainRegistry

protocol TopUpRequestViewModelMaking {
    func formatAmountValue(_ balance: Balance) -> String
    func tokenSymbol() -> String
    func amountMismatchWarning() -> String
    func amountMismatchTitle(productId: ProductId) -> String
}

final class TopUpRequestViewModelFactory {
    private let chainAsset: ChainAsset
    private let formatterFactory: AssetBalanceFormatterFactoryProtocol

    init(
        chainAsset: ChainAsset,
        formatterFactory: AssetBalanceFormatterFactoryProtocol = AssetBalanceFormatterFactory()
    ) {
        self.chainAsset = chainAsset
        self.formatterFactory = formatterFactory
    }
}

extension TopUpRequestViewModelFactory: TopUpRequestViewModelMaking {
    func formatAmountValue(_ balance: Balance) -> String {
        let decimalAmount = balance.decimal(assetInfo: chainAsset.asset.digitalDollarDisplayInfo)

        let formatter = formatterFactory
            .createTokenFormatter(for: chainAsset.asset.digitalDollarDisplayInfo.withoutSymbol)
            .value(for: .current)

        return formatter.stringFromDecimal(decimalAmount) ?? ""
    }

    func tokenSymbol() -> String {
        chainAsset.asset.digitalDollarDisplayInfo.symbol
    }

    func amountMismatchTitle(productId: ProductId) -> String {
        String(localized: .Products.topUpMismatchTitle(product: productId))
    }

    func amountMismatchWarning() -> String {
        String(localized: .Products.topUpAmountMismatchWarning)
    }
}
