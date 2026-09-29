import Foundation
import SubstrateSdk
import ChainRegistry

protocol ConfirmDepositViewModelMaking {
    func formatAmount(_ balance: Balance) -> String
}

final class ConfirmDepositViewModelFactory {
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

extension ConfirmDepositViewModelFactory: ConfirmDepositViewModelMaking {
    func formatAmount(_ balance: Balance) -> String {
        let decimalAmount = balance.decimal(assetInfo: chainAsset.assetDisplayInfo)

        let formatter = formatterFactory
            .createTokenFormatter(for: chainAsset.assetDisplayInfo)
            .value(for: .current)

        return formatter.stringFromDecimal(decimalAmount) ?? ""
    }
}
