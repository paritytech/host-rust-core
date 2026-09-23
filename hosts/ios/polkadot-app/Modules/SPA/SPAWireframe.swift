import UIKit
import Products
import UIKitExt

@MainActor
final class SPAWireframe: SPAWireframeProtocol, ChatNavigating {
    func openChat(
        from view: ControllerBackedProtocol?,
        chatId: Chat.Id
    ) {
        if let presentingController = view?.controller.navigationController?.presentingViewController {
            presentingController.dismiss(animated: true)
        } else {
            view?.controller.navigationController?.popToRootViewController(animated: true)
        }

        navigateToChat(with: chatId, force: false)
    }

    func showProductSPA(from _: ControllerBackedProtocol?, productHost: ProductHost) {
        UIApplication.shared.mainTabBarController?.openProduct(page: ProductPage(host: productHost))
    }

    func showMoreActions(
        from view: ControllerBackedProtocol?,
        actions: [SPAMoreAction],
        closeTitle: String
    ) {
        guard let view else { return }

        let sheet = SPAMoreActionsViewFactory.createView(
            actions: actions,
            closeTitle: closeTitle
        )
        view.controller.present(sheet.controller, animated: true)
    }

    func shareURL(_ url: URL, from view: ControllerBackedProtocol?) {
        guard let view else { return }

        let sheet = ShareViewFactory.createView(items: [.url(url)], host: view)
        view.controller.present(sheet.controller, animated: true)
    }

    func minimize(from view: ControllerBackedProtocol?) {
        guard !dismissIfPresented(view) else { return }

        UIApplication.shared.mainTabBarController?.minimizeSPA()
    }

    func close(tabId: UUID?, from view: ControllerBackedProtocol?) {
        guard !dismissIfPresented(view) else { return }
        guard let tabId else { return }

        UIApplication.shared.mainTabBarController?.closeSPA(tabId: tabId)
    }

    /// A product opened from a Pocket card is presented in its own stack rather
    /// than mounted in the tab container, so it is dismissed here. Everything
    /// else belongs to the browser and is handed back to it.
    private func dismissIfPresented(_ view: ControllerBackedProtocol?) -> Bool {
        let controller = view?.controller
        let presenting = controller?.navigationController?.presentingViewController
            ?? controller?.presentingViewController

        guard let presenting else { return false }

        presenting.dismiss(animated: true)
        return true
    }
}
