import UIKit
import UIKitExt

protocol TattooPhotoPreviewViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: TattooPhotoPreviewViewModel)
    func didStartLoading()
    func didStopLoading()
}

@MainActor
protocol TattooPhotoPreviewPresenterProtocol: AnyObject {
    func setup()
    func finishPreview()
    func confirmDiscard()
}

protocol TattooPhotoViewInteractorInputProtocol: AnyObject {
    func setup()
    func initiateUploading()
    func discardPhotoEvidence()
}

@MainActor
protocol TattooPhotoViewInteractorOutputProtocol: AnyObject {
    func didReceive(photoPreview: UIImage)
    func didInitiateEvidenceUploading()
    func didReceive(error: TattooPhotoPreviewInteractorError)
}

@MainActor
protocol TattooPhotoPreviewWireframeProtocol: AlertPresentable, ErrorPresentable, CommonRetryable {
    func showDiscardConfirmation(on view: TattooPhotoPreviewViewProtocol?, model: DiscardEvidenceModel)
    func goBackToCapturePhoto(from view: TattooPhotoPreviewViewProtocol?)
    func complete(from view: TattooPhotoPreviewViewProtocol?)
}

enum TattooPhotoPreviewInteractorError: Error {
    case photoLoading(Error)
    case photoFile(Error)
    case evidenceUploading(Error)
}
