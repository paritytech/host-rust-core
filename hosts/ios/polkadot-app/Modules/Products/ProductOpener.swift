import Foundation
import Products
import UIKit

@MainActor
enum ProductOpener {
    /// An existing tab keeps its current page; before the tab bar is up the link is deferred.
    static func open(productId: ProductId) {
        let tabBar = UIApplication.shared.mainTabBarController
        guard tabBar?.mountedProductId != productId else {
            return
        }
        guard tabBar?.mountExistingTab(where: { $0.dotDomain == productId }) != true,
              let url = URL(string: "\(AppConfig.ProductUniversalLink.scheme)://\(productId)") else {
            return
        }
        DeferredLinkHandler.shared.handle(with: url)
    }
}
