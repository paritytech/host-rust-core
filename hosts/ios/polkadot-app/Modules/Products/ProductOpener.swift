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
        if tabBar?.mountExistingTab(where: { $0.dotDomain == productId }) == true {
            return
        }

        if let tabBar,
           let host = ProductHostFactory(tldProvider: DotNsTldProviderFacade.shared).host(rawString: productId) {
            tabBar.openProduct(page: ProductPage(host: host, page: nil))
        } else if let url = URL(string: "https://\(productId)") {
            DeferredLinkHandler.shared.handle(with: url)
        }
    }
}
