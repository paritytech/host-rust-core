import Foundation

@MainActor
enum CollectiblesViewFactory {
    static func createView(
        url: URL,
        personDataStore: DetermineStatePersonDataStore
    ) -> CollectiblesViewProtocol? {
        let view = CollectiblesWebViewController(url: url)

        let collectionService = CollectiblesCollectionService(personDataStore: personDataStore)
        let interactor = CollectiblesInteractor(
            bridge: view.bridge,
            collectionService: collectionService
        )
        let wireframe = CollectiblesWireframe()
        let presenter = CollectiblesPresenter(interactor: interactor, wireframe: wireframe)

        view.presenter = presenter
        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
