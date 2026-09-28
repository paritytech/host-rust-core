import Products
import UIKit
import UIKitExt

final class WalletMainWireframe: WalletMainWireframeProtocol, AlertPresentable {
    private let personDataStore: DetermineStatePersonDataStore
    private let moduleNavigator: ModuleNavigating
    private let flowState: SPAFlowState

    init(
        personDataStore: DetermineStatePersonDataStore,
        flowState: SPAFlowState,
        moduleNavigator: ModuleNavigating = ModuleNavigator()
    ) {
        self.personDataStore = personDataStore
        self.flowState = flowState
        self.moduleNavigator = moduleNavigator
    }

    func showPocketCard(_ card: PocketCardViewModel) {
        PocketCardOpening.open(card, flowState: flowState, navigator: moduleNavigator)
    }

    func confirmPocketCardRemoval(_: PocketCardViewModel, onConfirm: @escaping () -> Void) {
        present(
            viewModel: AlertPresentableViewModel(
                title: String(localized: .pocketCardRemoveConfirmTitle),
                message: String(localized: .pocketCardRemoveConfirmMessage),
                actions: [
                    AlertPresentableAction(
                        title: String(localized: .pocketCardRemove),
                        style: .destructive,
                        handler: onConfirm
                    )
                ],
                closeActionTitle: String(localized: .pocketAddCardCancel)
            ),
            style: .alert,
            from: nil
        )
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
