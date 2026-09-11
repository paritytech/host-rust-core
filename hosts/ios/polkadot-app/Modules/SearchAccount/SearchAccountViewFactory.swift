import Foundation
import Coinage
import ChainRegistry

@MainActor
enum SearchAccountViewFactory {
    static func createView(
        for chainAsset: ChainAsset,
        coinageServicing: CoinageServicing
    ) -> SearchAccountViewProtocol? {
        let logger = Logger.shared
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let recentContactsService = RecentContactsService(
            recentContactsSubscriptionFactory: RecentContactsSubscriptionFactory.shared,
            identityQueryFactory: IdentityPalletQueryFactory(
                operationQueue: operationQueue
            ),
            chainRegistry: chainRegistry,
            usernameChainId: AppConfig.Chains.usernameChain,
            operationQueue: operationQueue,
            logger: logger
        )
        let searchUsernameFactory = SearchUsernameFactory(
            chatContactRepositoryFactory: ChatContactRepositoryFactory(),
            chainModel: chainAsset.chain
        )
        let interactor = SearchAccountInteractor(
            searchUsernameFactory: searchUsernameFactory,
            recentContactsManager: recentContactsService,
            logger: logger
        )
        let wireframe = SearchAccountWireframe(coinageServicing: coinageServicing)
        let presenter = SearchAccountPresenter(
            interactor: interactor,
            wireframe: wireframe,
            recipientViewModelFactory: RecipientViewModelFactory(),
            logger: logger,
            chainAsset: chainAsset
        )

        let view = SearchAccountViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
