import Foundation
import Products
import UIKit
import UIKitExt

/// Brings a product's SPA forward for a game reminder, over whatever is on screen: a presented sheet is dismissed
/// first and its flow counts as refused.
@MainActor
enum GameReminderProductOpener {
    static func open(
        productId: ProductId,
        hostProvider: ProductHostProviding = ProductHostFactory(tldProvider: DotNsTldProviderFacade.shared)
    ) {
        guard let tabBar = UIApplication.shared.mainTabBarController else {
            openThroughLink(productId: productId)
            return
        }

        let openProduct = {
            if let host = hostProvider.host(rawString: productId) {
                tabBar.openProduct(page: ProductPage(host: host))
            } else {
                openThroughLink(productId: productId)
            }
        }

        if let presented = tabBar.presentedViewController, !(presented is TransientPresentationSkipping) {
            tabBar.dismiss(animated: true, completion: openProduct)
        } else {
            openProduct()
        }
    }

    private static func openThroughLink(productId: ProductId) {
        guard let url = GameReminderProductLink.url(for: productId) else {
            return
        }
        DeferredLinkHandler.shared.handle(with: url)
    }
}
