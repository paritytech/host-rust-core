import Foundation

@MainActor
final class CollectiblesPresenter {
    weak var view: CollectiblesViewProtocol?

    private let interactor: CollectiblesInteractorInputProtocol
    private let wireframe: CollectiblesWireframeProtocol

    init(
        interactor: CollectiblesInteractorInputProtocol,
        wireframe: CollectiblesWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension CollectiblesPresenter: CollectiblesPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func close() {
        wireframe.close(view: view)
    }
}

extension CollectiblesPresenter: CollectiblesInteractorOutputProtocol {
    func didReceive(collection: CollectionInput) {
        view?.didReceive(collection: collection)
    }

    func didRequestClose() {
        wireframe.close(view: view)
    }
}
