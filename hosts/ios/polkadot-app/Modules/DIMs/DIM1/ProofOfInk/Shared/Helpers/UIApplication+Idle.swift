import UIKit

protocol ApplicationIdleStateMediating: AnyObject {
    /// A Boolean value that controls whether the idle timer is disabled for the app.
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: ApplicationIdleStateMediating {}
