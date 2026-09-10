import UIKit

final class WalletMainWireframe: WalletMainWireframeProtocol {
    private let personDataStore: DetermineStatePersonDataStore

    init(personDataStore: DetermineStatePersonDataStore) {
        self.personDataStore = personDataStore
    }

    func showCollectibles(from view: WalletMainViewProtocol?, url: URL) {
        guard let collectiblesView = CollectiblesViewFactory.createView(
            url: url,
            personDataStore: personDataStore
        ) else {
            return
        }

        let nav = AppNavigationController(rootViewController: collectiblesView.controller)
        nav.modalPresentationStyle = .fullScreen

        view?.controller.present(nav, animated: true)
    }
}
