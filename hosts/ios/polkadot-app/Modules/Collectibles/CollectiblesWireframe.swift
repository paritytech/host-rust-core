import UIKit

final class CollectiblesWireframe: CollectiblesWireframeProtocol {
    func close(view: CollectiblesViewProtocol?) {
        view?.controller.presentingViewController?.dismiss(animated: true)
    }
}
