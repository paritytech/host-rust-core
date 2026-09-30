import UIKit
import Products

#if !FEATURE_PRODUCTS
    extension MainTabBarViewController {
        /// Without the browse tab a product is a one-shot rather than a peer of the tabs: it is
        /// presented over the container, so it never enters the tab store and closing it leaves
        /// no chip behind.
        func presentProduct(page: ProductPage) {
            guard let view = SPAViewFactory.createView(
                page: page,
                flowState: flowStateProvider.flowState(),
                isBrowserTab: true
            ) else {
                return
            }

            view.controller.modalPresentationStyle = .pageSheet
            view.controller.sheetPresentationController?.detents = [
                .custom { $0.maximumDetentValue * 0.92 }
            ]
            view.controller.sheetPresentationController?.prefersGrabberVisible = true

            let host = UIWindow.keyWindow?.topmostViewController ?? self
            host.present(view.controller, animated: true)
        }
    }
#endif
