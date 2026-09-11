import Foundation

final class DiscardEvidenceWireframe: DiscardEvidenceWireframeProtocol {
    func close(view: DiscardEvidenceViewProtocol?, _ completion: (() -> Void)?) {
        view?.controller.dismiss(animated: true, completion: completion)
    }
}
