import Foundation
import Individuality

@MainActor
enum TattooVideoPreviewViewFactory {
    static func createView(
        for recordings: [URL],
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    ) -> TattooVideoPreviewViewProtocol? {
        let interactor = createInteractor(for: recordings, evidenceId: evidenceId)
        let wireframe = TattooVideoPreviewWireframe(design: design, familyId: familyId)

        let presenter = TattooVideoPreviewPresenter(
            interactor: interactor,
            wireframe: wireframe,
            logger: Logger.shared
        )

        let view = TattooVideoPreviewViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }

    private static func createInteractor(for recordings: [URL], evidenceId: String) -> TattooVideoPreviewInteractor {
        let evidenceFileManagerFactory = EvidenceFileManagerFactory()
        let fileManager = evidenceFileManagerFactory.createManager(evidenceId: evidenceId)
        return .init(
            videoExportingService: VideoExportService(logger: Logger.shared),
            fileManager: fileManager,
            recordings: recordings,
            stateMediator: ProvideEvidenceStateMediator(fileManager: fileManager)
        )
    }
}
