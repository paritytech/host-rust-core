import Foundation

@MainActor
enum TattooPhotoPreviewViewFactory {
    static func createView(evidenceId: String) -> TattooPhotoPreviewViewProtocol? {
        let factory = EvidenceStateRepositoryFactory(
            substrateFacade: SubstrateDataStorageFacade.shared
        )

        let evidenceFileManagerFactory = EvidenceFileManagerFactory()
        let interactor = TattooPhotoPreviewInteractor(
            fileManager: evidenceFileManagerFactory.createManager(evidenceId: evidenceId),
            localStateRepository: factory.createLocalStateRepository(),
            operationQueue: OperationManagerFacade.sharedDefaultQueue
        )

        let wireframe = TattooPhotoPreviewWireframe()

        let presenter = TattooPhotoPreviewPresenter(
            interactor: interactor,
            wireframe: wireframe,
            logger: Logger.shared
        )

        let view = TattooPhotoPreviewViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
