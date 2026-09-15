import UIKit

@MainActor
final class TattooPhotoPreviewPresenter {
    weak var view: TattooPhotoPreviewViewProtocol?
    let wireframe: TattooPhotoPreviewWireframeProtocol
    let interactor: TattooPhotoViewInteractorInputProtocol
    private let logger: LoggerProtocol

    init(
        interactor: TattooPhotoViewInteractorInputProtocol,
        wireframe: TattooPhotoPreviewWireframeProtocol,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.logger = logger
    }

    private func discardPhotoEvidence() {
        interactor.discardPhotoEvidence()
        wireframe.goBackToCapturePhoto(from: view)
    }

    private func provideViewModel(photoPreview: UIImage) {
        let viewModel = TattooPhotoPreviewViewModel(
            mainAction: String(localized: .Tattoo.evidencePhotoActionDone),
            photoPreview: photoPreview
        )
        view?.didReceive(viewModel: viewModel)
    }
}

extension TattooPhotoPreviewPresenter: TattooPhotoPreviewPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func finishPreview() {
        view?.didStartLoading()

        interactor.initiateUploading()
    }

    func confirmDiscard() {
        let model = DiscardEvidenceModel(
            mode: .photo,
            discardClosure: discardPhotoEvidence
        )
        wireframe.showDiscardConfirmation(on: view, model: model)
    }
}

extension TattooPhotoPreviewPresenter: TattooPhotoViewInteractorOutputProtocol {
    func didReceive(error: TattooPhotoPreviewInteractorError) {
        logger.error("Did receive TattooPhotoPreviewInteractorError: \(error)")

        view?.didStopLoading()

        wireframe.presentRequestStatus(on: view) { [weak self] in
            self?.interactor.setup()
        }
    }

    func didReceive(photoPreview: UIImage) {
        provideViewModel(photoPreview: photoPreview)
    }

    func didInitiateEvidenceUploading() {
        logger.debug("Did complete")

        wireframe.complete(from: view)
    }
}
