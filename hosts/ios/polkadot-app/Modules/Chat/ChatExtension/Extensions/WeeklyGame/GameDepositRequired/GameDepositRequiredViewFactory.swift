import Foundation
import SubstrateSdk
import ChainRegistry

@MainActor
enum GameDepositRequiredViewFactory {
    static func createView(
        requiredBalance: Balance,
        asset: ChainAssetId,
        model: GameDepositRequiredModel
    ) -> GameDepositRequiredViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let chain = chainRegistry.getChain(for: asset.chainId),
            let asset = chain.chainAsset(for: asset.assetId)
        else {
            return nil
        }

        let viewModelFactory = GameDepositRequiredViewModelFactory(chainAsset: asset)

        let presenter = GameDepositRequiredPresenter(
            requiredBalance: requiredBalance,
            model: model,
            viewModelFactory: viewModelFactory
        )

        let view = GameDepositRequiredViewController(presenter: presenter)

        presenter.view = view

        BottomSheetViewFacade.setupBottomSheet(from: view.controller, preferredHeight: nil)

        return view
    }
}
