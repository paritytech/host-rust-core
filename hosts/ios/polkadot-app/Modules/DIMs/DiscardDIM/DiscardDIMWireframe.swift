import Foundation

final class DiscardDIMWireframe: DiscardDIMWireframeProtocol {
    func close(view: DiscardDIMViewProtocol?, completion: (() -> Void)?) {
        view?.controller.dismiss(animated: true, completion: completion)
    }
}
