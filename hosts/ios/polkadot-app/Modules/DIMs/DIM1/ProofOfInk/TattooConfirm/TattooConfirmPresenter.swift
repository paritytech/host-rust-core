import Foundation
import Foundation_iOS
import UIKit
import PolkadotUI

@MainActor
final class TattooConfirmPresenter {
    weak var view: TattooConfirmViewProtocol?
    let wireframe: TattooConfirmWireframeProtocol
    let model: TattooConfirmModel

    init(
        model: TattooConfirmModel,
        wireframe: TattooConfirmWireframeProtocol
    ) {
        self.model = model
        self.wireframe = wireframe
    }
}

extension TattooConfirmPresenter: TattooConfirmPresenterProtocol {
    func cancel() {
        wireframe.close(view: view, completion: model.cancelClosure)
    }

    func confirm() {
        wireframe.close(view: view, completion: model.confirmClosure)
    }
}
