import Foundation

final class TattooEvidencePhotoWireframe: TattooEvidencePhotoWireframeProtocol {
    let evidenceId: String

    init(evidenceId: String) {
        self.evidenceId = evidenceId
    }

    func showPhotoTips(from view: TattooEvidencePhotoViewProtocol?) {
        let mode: EvidenceTipsMode = .photo
        let viewToPresent = EvidenceTipsViewFactory.createView(mode: mode)
        BottomSheetViewFacade.setupBottomSheet(from: viewToPresent.controller, preferredHeight: mode.preferredHeight)
        view?.controller.present(viewToPresent.controller, animated: true)
    }

    func presentPhotoPreview(from view: TattooEvidencePhotoViewProtocol?) {
        guard let viewToPresent = TattooPhotoPreviewViewFactory.createView(evidenceId: evidenceId) else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            viewToPresent.controller,
            animated: true
        )
    }
}
