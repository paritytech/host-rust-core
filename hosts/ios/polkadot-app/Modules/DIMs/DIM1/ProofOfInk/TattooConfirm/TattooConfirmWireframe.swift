import Foundation

final class TattooConfirmWireframe: TattooConfirmWireframeProtocol {
    func close(view: TattooConfirmViewProtocol?, completion: (() -> Void)?) {
        view?.controller.dismiss(animated: true, completion: completion)
    }
}
