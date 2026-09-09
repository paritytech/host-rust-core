import Foundation
import Foundation_iOS
import Individuality
import UIKit

@MainActor
enum TattooEvidenceVideoViewFactory {
    static func createView(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    ) -> TattooEvidenceVideoViewProtocol? {
        let interactor = createInteractor(evidenceId: evidenceId)
        let wireframe = TattooEvidenceVideoWireframe(design: design, familyId: familyId, evidenceId: evidenceId)

        let presenter = TattooEvidenceVideoPresenter(
            interactor: interactor,
            wireframe: wireframe,
            logger: Logger.shared
        )

        let view = TattooEvidenceVideoViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }

    static func createInteractor(evidenceId: String) -> TattooEvidenceVideoInteractor {
        let evidenceFileManagerFactory = EvidenceFileManagerFactory()
        let fileManager = evidenceFileManagerFactory.createManager(evidenceId: evidenceId)
        return TattooEvidenceVideoInteractor(
            videoCaptureService: VideoCaptureService(delegate: nil),
            fileManager: fileManager,
            stateMediator: ProvideEvidenceStateMediator(fileManager: fileManager),
            idleStateMediator: UIApplication.shared
        )
    }
}
