import UIKit

final class DiscardNotificationsWireframe: DiscardNotificationsWireframeProtocol {
    func close(view: DiscardNotificationsViewProtocol?, completion: (() -> Void)?) {
        view?.controller.dismiss(animated: true, completion: completion)
    }
}
