import UIKit

public extension UIViewController {
    /// The controller that should receive a `present` call when `self` is used
    /// as a presentation anchor. Resolved at call time so sheets land above any
    /// modal already covering the anchor instead of silently failing to present.
    var topmostPresented: UIViewController {
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topmostPresented
        }

        if let presentedViewController {
            return presentedViewController.topmostPresented
        }

        if let provider = self as? TopmostChildProviding,
           let topmostChild = provider.topmostChild {
            return topmostChild.topmostPresented
        }

        return self
    }
}
