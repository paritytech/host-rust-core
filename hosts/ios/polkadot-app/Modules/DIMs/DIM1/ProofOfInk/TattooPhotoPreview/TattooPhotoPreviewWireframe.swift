import Foundation

@MainActor
final class TattooPhotoPreviewWireframe: TattooPhotoPreviewWireframeProtocol {
    func showDiscardConfirmation(on view: TattooPhotoPreviewViewProtocol?, model: DiscardEvidenceModel) {
        guard let viewToPresent = DiscardEvidenceViewFactory.createView(for: model) else {
            return
        }

        view?.controller.present(viewToPresent.controller, animated: true)
    }

    func goBackToCapturePhoto(from view: TattooPhotoPreviewViewProtocol?) {
        view?.controller.navigationController?.popViewController(animated: true)
    }

    func complete(from view: TattooPhotoPreviewViewProtocol?) {
        view?.controller.navigationController?.dismiss(animated: true)
    }
}
