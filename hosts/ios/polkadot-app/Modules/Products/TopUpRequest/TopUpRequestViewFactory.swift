import Foundation
import SubstrateSdk
import ChainRegistry

@MainActor
enum TopUpRequestViewFactory {
    static func createMismatchView(
        context: TopUpRequestContext,
        claimedAmount: Balance,
        requestedAmount: Balance
    ) -> TopUpMismatchViewProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let chainAssetId = AppConfig.Assets.mainAsset

        guard
            let chain = chainRegistry.getChain(for: chainAssetId.chainId),
            let chainAsset = chain.chainAsset(for: chainAssetId.assetId)
        else {
            return nil
        }

        let viewModelFactory = TopUpRequestViewModelFactory(chainAsset: chainAsset)

        let wireframe = TopUpMismatchWireframe()
        let presenter = TopUpMismatchPresenter(
            wireframe: wireframe,
            context: context,
            claimedAmount: claimedAmount,
            requestedAmount: requestedAmount,
            viewModelFactory: viewModelFactory
        )
        let view = TopUpMismatchViewController(presenter: presenter)
        presenter.view = view

        BottomSheetViewFacade.setupNonNavigatingSheet(from: view, preferredHeight: nil)
        return view
    }

    static func createErrorView(
        context: TopUpRequestContext,
        error: Error
    ) -> TopUpErrorViewProtocol {
        let message = String(localized: .Products.topUpErrorMessage)

        let wireframe = TopUpErrorWireframe()
        let presenter = TopUpErrorPresenter(
            wireframe: wireframe,
            context: context,
            error: error,
            title: String(localized: .Products.topUpErrorTitle(product: context.productId)),
            message: message,
            closeButtonTitle: String(localized: .Common.close)
        )
        let view = TopUpErrorViewController(presenter: presenter)
        presenter.view = view

        BottomSheetViewFacade.setupNonNavigatingSheet(from: view, preferredHeight: nil)
        return view
    }
}
