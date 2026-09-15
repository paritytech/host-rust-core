import AVFoundation
import UIKit
import UIKitExt

protocol TattooEvidencePhotoViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: TattooEvidencePhotoViewModel)
    func didReceive(state: TattooEvidencePhotoViewState)
    func didReceive(session: AVCaptureSession)
}

@MainActor
protocol TattooEvidencePhotoPresenterProtocol: AnyObject {
    func setup()
    func willAppear()
    func capturePhoto()
    func toggleTattooOutline()
    func showPhotoTips()
}

protocol TattooEvidencePhotoInteractorInputProtocol: AnyObject {
    func setup()
    func capturePhoto()
}

@MainActor
protocol TattooEvidencePhotoInteractorOutputProtocol: AnyObject {
    func didReceive(session: AVCaptureSession)
    func didReceive(state: TattooEvidencePhotoViewState)
    func didReceive(error: TattooEvidencePhotoError)
    func didSaveCapturedPhoto()
}

@MainActor
protocol TattooEvidencePhotoWireframeProtocol: AnyObject {
    func showPhotoTips(from view: TattooEvidencePhotoViewProtocol?)
    func presentPhotoPreview(from view: TattooEvidencePhotoViewProtocol?)
}

enum TattooEvidencePhotoError: Error {
    case storageError(Error)
    case photoCapture(PhotoCaptureServiceError)
}
