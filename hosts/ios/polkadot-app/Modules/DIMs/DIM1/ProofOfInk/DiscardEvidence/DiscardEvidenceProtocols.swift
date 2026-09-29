import UIKitExt

protocol DiscardEvidenceViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: DiscardEvidenceViewModel)
}

@MainActor
protocol DiscardEvidencePresenterProtocol: AnyObject {
    func setup()
    func cancel()
    func discard()
}

@MainActor
protocol DiscardEvidenceWireframeProtocol: AnyObject {
    func close(view: DiscardEvidenceViewProtocol?, _ completion: (() -> Void)?)
}
