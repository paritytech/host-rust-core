import Foundation
import SubstrateSdk
import ChainRegistry

@MainActor
enum ConfirmDepositViewFactory {
    static func createView(
        asset: ChainAssetId,
        amount: Balance,
        model: ConfirmDepositModel
    ) -> ConfirmDepositViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        guard
            let chain = chainRegistry.getChain(for: asset.chainId),
            let asset = chain.chainAsset(for: asset.assetId),
            let candidateWallet = try? walletRepo.candidate()
        else {
            return nil
        }
        let interactor = ConfirmDepositInteractor(
            candidateWallet: candidateWallet,
            chainAsset: asset,
            logger: Logger.shared
        )
        let viewModelFactory = ConfirmDepositViewModelFactory(chainAsset: asset)

        let presenter = ConfirmDepositPresenter(
            interactor: interactor,
            amount: amount,
            chainAsset: asset,
            model: model,
            viewModelFactory: viewModelFactory
        )

        let view = ConfirmDepositViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        BottomSheetViewFacade.setupBottomSheet(from: view.controller, preferredHeight: nil)

        return view
    }
}
