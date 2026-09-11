import Foundation

final class TattooVideoPreviewPresenter {
    weak var view: TattooVideoPreviewViewProtocol?
    let wireframe: TattooVideoPreviewWireframeProtocol
    let interactor: TattooVideoPreviewInteractorInputProtocol
    let logger: LoggerProtocol

    private var videoUrl: URL?

    init(
        interactor: TattooVideoPreviewInteractorInputProtocol,
        wireframe: TattooVideoPreviewWireframeProtocol,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.logger = logger
    }
}

extension TattooVideoPreviewPresenter: TattooVideoPreviewPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func nextEvidence() {
        guard videoUrl != nil else {
            return
        }
        interactor.confirmVideo()
        wireframe.showNextEvidence(from: view)
    }

    func confirmDiscard() {
        let model = DiscardEvidenceModel(
            mode: .video,
            discardClosure: saveAndDiscardVideoEvidence
        )
        wireframe.showDiscardConfirmation(on: view, model: model)
    }

    @MainActor
    func saveAndDiscardVideoEvidence() {
        wireframe.goBackToCaptureVideo(from: view)
    }
}

extension TattooVideoPreviewPresenter: TattooVideoPreviewInteractorOutputProtocol {
    func didReceive(error: TattooVideoPreviewInteractorError) {
        logger.error("Did receive error: \(error)")

        wireframe.presentRequestStatus(on: view) { [weak self] in
            self?.interactor.setup()
        }
    }

    func didReceive(videoUrl: URL) {
        logger.debug("Video url: \(videoUrl)")

        self.videoUrl = videoUrl

        view?.didReceive(videoUrl: videoUrl)
    }
}
