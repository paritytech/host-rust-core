import UIKitExt

protocol EvidenceTipsViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: EvidenceTipsViewModel)
}

@MainActor
protocol EvidenceTipsPresenterProtocol: AnyObject {
    func setup()
}

@MainActor
protocol EvidenceTipsWireframeProtocol: AnyObject {}
