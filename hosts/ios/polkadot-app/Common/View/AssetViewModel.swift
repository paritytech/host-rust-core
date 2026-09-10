import Foundation

struct AssetAmountViewModel {
    let symbol: String
    let isSymbolInFront: Bool
    let assetViewModel: AssetView.ViewModel?
}

struct AssetSymbolViewModel {
    let symbol: String
    let asset: AssetView.ViewModel
}
