import UIKit
import PolkadotUI
import UIKitExt

protocol EvidenceInstructionsViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: InstructionSheetViewModel)
}

@MainActor
protocol EvidenceInstructionsPresenterProtocol: AnyObject {
    func setup()
    func willDisappear()
    func didTapClose()
    func didTapProceed()
}

@MainActor
protocol EvidenceInstructionsWireframeProtocol: AnyObject {
    func close(view: EvidenceInstructionsViewProtocol?, completion: (() -> Void)?)
    func showLowStorage(from view: EvidenceInstructionsViewProtocol?, onProceed: @escaping () -> Void)
    func showLowBattery(from view: EvidenceInstructionsViewProtocol?, onProceed: @escaping () -> Void)
}
