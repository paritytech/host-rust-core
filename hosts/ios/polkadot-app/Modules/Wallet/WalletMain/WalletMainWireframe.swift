import Products
import UIKit
import UIKitExt

final class WalletMainWireframe: WalletMainWireframeProtocol {
    private let personDataStore: DetermineStatePersonDataStore
    private let moduleNavigator: ModuleNavigating
    private let hostProvider: any ProductHostProviding

    init(
        personDataStore: DetermineStatePersonDataStore,
        hostProvider: any ProductHostProviding,
        moduleNavigator: ModuleNavigating = ModuleNavigator()
    ) {
        self.personDataStore = personDataStore
        self.hostProvider = hostProvider
        self.moduleNavigator = moduleNavigator
    }

    func showPocketCard(_ card: PocketCardViewModel) {
        PocketCardOpening.open(card.key, hostProvider: hostProvider, navigator: moduleNavigator)
    }

    func confirmPocketCardRemoval(_: PocketCardViewModel, onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(
            title: String(localized: .pocketCardRemoveConfirmTitle),
            message: String(localized: .pocketCardRemoveConfirmMessage),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: .pocketAddCardCancel), style: .cancel))
        alert.addAction(
            UIAlertAction(title: String(localized: .pocketCardRemove), style: .destructive) { _ in onConfirm() }
        )

        UIWindow.topWindow?.topmostViewController?.present(alert, animated: true)
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
