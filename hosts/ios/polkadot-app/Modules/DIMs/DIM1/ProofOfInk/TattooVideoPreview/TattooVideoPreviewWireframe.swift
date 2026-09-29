import Foundation
import Individuality

@MainActor
final class TattooVideoPreviewWireframe: TattooVideoPreviewWireframeProtocol {
    let design: ProofOfInkPallet.InkSpec
    let familyId: ProofOfInkPallet.FamilyId

    init(design: ProofOfInkPallet.InkSpec, familyId: ProofOfInkPallet.FamilyId) {
        self.design = design
        self.familyId = familyId
    }

    func showNextEvidence(from view: TattooVideoPreviewViewProtocol?) {
        let currentPresenter = view?.controller.navigationController?.presentingViewController
        currentPresenter?.dismiss(animated: true)
    }

    func showDiscardConfirmation(on view: TattooVideoPreviewViewProtocol?, model: DiscardEvidenceModel) {
        guard let viewToPresent = DiscardEvidenceViewFactory.createView(for: model) else {
            return
        }

        view?.controller.present(viewToPresent.controller, animated: true)
    }

    func goBackToCaptureVideo(from view: TattooVideoPreviewViewProtocol?) {
        view?.controller.navigationController?.popViewController(animated: true)
    }
}
