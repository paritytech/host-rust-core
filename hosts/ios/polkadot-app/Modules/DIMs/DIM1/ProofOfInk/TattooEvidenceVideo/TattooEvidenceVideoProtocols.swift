import AVFoundation
import UIKitExt

protocol TattooEvidenceVideoViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: TattooEvidenceVideoViewModel)
}

@MainActor
protocol TattooEvidenceVideoPresenterProtocol: AnyObject {
    func setup()
    func toggleRecording()
    func openTips()
}

protocol TattooEvidVideoInteractorInputProtocol: AnyObject {
    func setup()
    func start()
    func complete()
    func discard()
}

@MainActor
protocol TattooEvidVideoInteractorOutputProtocol: AnyObject {
    func didReceive(captureSession: AVCaptureSession)
    func didDiscardRecording()
    func didCompleteRecording(with urls: [URL])
    func didReceive(error: TattooEvidVideoInteractorError)
}

@MainActor
protocol TattooEvidenceVideoWireframeProtocol: AlertPresentable, ErrorPresentable,
    ApplicationSettingsPresentable {
    func showTips(from view: TattooEvidenceVideoViewProtocol?)
    func showPreview(from view: TattooEvidenceVideoViewProtocol?, recordings: [URL])
}
