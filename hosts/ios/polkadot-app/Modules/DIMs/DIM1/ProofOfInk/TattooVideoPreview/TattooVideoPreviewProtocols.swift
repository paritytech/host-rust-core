import Foundation
import UIKitExt

protocol TattooVideoPreviewViewProtocol: ControllerBackedProtocol {
    func didReceive(videoUrl: URL)
}

@MainActor
protocol TattooVideoPreviewPresenterProtocol: AnyObject {
    func setup()
    func nextEvidence()
    func confirmDiscard()
}

protocol TattooVideoPreviewInteractorInputProtocol: AnyObject {
    func setup()
    func confirmVideo()
}

@MainActor
protocol TattooVideoPreviewInteractorOutputProtocol: AnyObject {
    func didReceive(error: TattooVideoPreviewInteractorError)
    func didReceive(videoUrl: URL)
}

@MainActor
protocol TattooVideoPreviewWireframeProtocol: AlertPresentable, ErrorPresentable, CommonRetryable {
    func showNextEvidence(from view: TattooVideoPreviewViewProtocol?)
    func showDiscardConfirmation(on view: TattooVideoPreviewViewProtocol?, model: DiscardEvidenceModel)
    func goBackToCaptureVideo(from view: TattooVideoPreviewViewProtocol?)
}
