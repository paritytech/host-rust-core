import UIKit
import UIKitExt

/// Tells the user a Pocket link went nowhere.
///
/// A link the host claimed but cannot serve must say so: staying silent reads
/// as the app having ignored the tap, and the user retries it.
@MainActor
enum PocketRefusalPresenter {
    static func show(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: .pocketAlertOk), style: .default))

        UIWindow.topWindow?.topmostViewController?.present(alert, animated: true)
    }
}
