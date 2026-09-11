import Foundation
import Individuality

@MainActor
enum TattooEvidencePhotoViewFactory {
    static func createView(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    ) -> TattooEvidencePhotoViewProtocol? {
        let photoCaptureService = PhotoCaptureService()
        let evidenceFileManagerFactory = EvidenceFileManagerFactory()
        let interactor = TattooEvidencePhotoInteractor(
            photoCaptureService: photoCaptureService,
            fileManager: evidenceFileManagerFactory.createManager(evidenceId: evidenceId),
            logger: Logger.shared
        )
        let wireframe = TattooEvidencePhotoWireframe(evidenceId: evidenceId)

        let presenter = TattooEvidencePhotoPresenter(
            interactor: interactor,
            wireframe: wireframe,
            design: design,
            familyId: familyId,
            tattooImageViewModelFactory: TattooImageViewModelFactory(),
            logger: Logger.shared
        )

        let view = TattooEvidencePhotoViewController(presenter: presenter)

        photoCaptureService.use(delegate: interactor)
        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
