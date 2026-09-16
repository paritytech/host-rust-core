import Foundation

@MainActor
final class SearchContactWireframe: SearchContactWireframeProtocol {
    let model: SearchContactModel

    init(model: SearchContactModel) {
        self.model = model
    }

    func complete(from view: SearchContactViewProtocol?, with model: ChatOpenModel) {
        view?.controller.dismiss(animated: true) { [weak self] in
            self?.model.didFoundChat(model)
        }
    }
}
