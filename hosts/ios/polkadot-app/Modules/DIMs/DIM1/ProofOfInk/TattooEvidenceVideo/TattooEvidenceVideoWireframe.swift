import Foundation
import Individuality

@MainActor
final class TattooEvidenceVideoWireframe: TattooEvidenceVideoWireframeProtocol {
    let design: ProofOfInkPallet.InkSpec
    let familyId: ProofOfInkPallet.FamilyId
    let evidenceId: String

    init(design: ProofOfInkPallet.InkSpec, familyId: ProofOfInkPallet.FamilyId, evidenceId: String) {
        self.design = design
        self.familyId = familyId
        self.evidenceId = evidenceId
    }

    func showTips(from view: TattooEvidenceVideoViewProtocol?) {
        let mode: EvidenceTipsMode = .video
        let viewToPresent = EvidenceTipsViewFactory.createView(mode: mode)
        BottomSheetViewFacade.setupBottomSheet(from: viewToPresent.controller, preferredHeight: mode.preferredHeight)
        view?.controller.present(viewToPresent.controller, animated: true)
    }

    func showPreview(from view: TattooEvidenceVideoViewProtocol?, recordings: [URL]) {
        guard let previewView = TattooVideoPreviewViewFactory.createView(
            for: recordings,
            design: design,
            familyId: familyId,
            evidenceId: evidenceId
        ) else {
            return
        }

        view?.controller.navigationController?.pushViewController(previewView.controller, animated: true)
    }
}
