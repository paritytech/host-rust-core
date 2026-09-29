import UIKitExt

protocol CollectiblesViewProtocol: ControllerBackedProtocol {
    func didReceive(collection: CollectionInput)
}

@MainActor
protocol CollectiblesPresenterProtocol: AnyObject {
    func setup()
    func close()
}

protocol CollectiblesInteractorInputProtocol: AnyObject {
    func setup()
}

@MainActor
protocol CollectiblesInteractorOutputProtocol: AnyObject {
    func didReceive(collection: CollectionInput)
    func didRequestClose()
}

@MainActor
protocol CollectiblesWireframeProtocol: AnyObject {
    func close(view: CollectiblesViewProtocol?)
}
