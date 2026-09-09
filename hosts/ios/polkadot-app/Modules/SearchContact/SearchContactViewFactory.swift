import Foundation
import Coinage

@MainActor
enum SearchContactViewFactory {
    static func createView(
        with model: SearchContactModel,
        coinageService: CoinageServicing
    ) -> SearchContactViewProtocol? {
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        guard let ownAccountId = try? walletRepo.main().getRawPublicKey() else {
            assertionFailure()
            return nil
        }

        let interactor = SearchContactInteractor(ownAccountId: ownAccountId)
        let wireframe = SearchContactWireframe(model: model, coinageService: coinageService)

        let presenter = SearchContactPresenter(
            interactor: interactor,
            wireframe: wireframe
        )

        let view = SearchContactViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
