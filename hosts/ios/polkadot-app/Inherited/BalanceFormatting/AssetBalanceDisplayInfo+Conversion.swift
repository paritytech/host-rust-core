import Foundation
import Foundation_iOS
import ChainRegistry

extension AssetModel {
    var displayInfo: AssetBalanceDisplayInfo {
        AssetBalanceDisplayInfo(
            displayPrecision: 3,
            assetPrecision: Int16(bitPattern: precision),
            symbol: symbol,
            symbolValueSeparator: " ",
            symbolPosition: .suffix,
            icon: icon
        )
    }

    var digitalDollarDisplayInfo: AssetBalanceDisplayInfo {
        AssetBalanceDisplayInfo(
            displayPrecision: 2,
            assetPrecision: Int16(bitPattern: precision),
            symbol: AppConfig.Brand.cashSymbol,
            symbolValueSeparator: " ",
            symbolPosition: .suffix,
            icon: nil
        )
    }
}

extension ChainAsset {
    var assetDisplayInfo: AssetBalanceDisplayInfo { asset.displayInfo }
}

extension AssetBalanceDisplayInfo {
    static var usd: AssetBalanceDisplayInfo {
        AssetBalanceDisplayInfo(
            displayPrecision: 2,
            assetPrecision: 2,
            symbol: AppConfig.Brand.fiatSymbol,
            symbolValueSeparator: "",
            symbolPosition: .prefix,
            icon: nil
        )
    }

    var withoutSymbol: AssetBalanceDisplayInfo {
        AssetBalanceDisplayInfo(
            displayPrecision: displayPrecision,
            assetPrecision: assetPrecision,
            symbol: "",
            symbolValueSeparator: symbolValueSeparator,
            symbolPosition: symbolPosition,
            icon: icon
        )
    }
}
