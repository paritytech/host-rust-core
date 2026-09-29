import Foundation
import PolkadotUI

@MainActor
final class EvidenceInstructionsPresenter {
    weak var view: EvidenceInstructionsViewProtocol?
    private let wireframe: EvidenceInstructionsWireframeProtocol
    private let viewModelProvider: EvidenceInstructionsViewModelProviderProtocol
    private let model: EvidenceInstructionsModel
    private let interactor: EvidenceInstructionsInteractorInputProtocol

    private var deviceStatus: ProvideEvidenceDeviceStatus?

    init(
        model: EvidenceInstructionsModel,
        wireframe: EvidenceInstructionsWireframeProtocol,
        viewModelProvider: EvidenceInstructionsViewModelProviderProtocol,
        interactor: EvidenceInstructionsInteractorInputProtocol
    ) {
        self.model = model
        self.wireframe = wireframe
        self.viewModelProvider = viewModelProvider
        self.interactor = interactor
    }
}

extension EvidenceInstructionsPresenter: EvidenceInstructionsPresenterProtocol {
    func setup() {
        let viewModel = viewModelProvider.createViewModel()
        view?.didReceive(viewModel: viewModel)
    }

    func willDisappear() {
        interactor.stopMonitoringDeviceStatus()
    }

    func didTapClose() {
        wireframe.close(view: view) { [model] in
            model.onClose()
        }
    }

    func didTapProceed() {
        interactor.updateDeviceStatus()
        validateDeviceStatus(onSuccess: proceedAndClose)
    }
}

extension EvidenceInstructionsPresenter: EvidenceInstructionsInteractorOutputProtocol {
    func didUpdate(deviceStatus: ProvideEvidenceDeviceStatus) {
        self.deviceStatus = deviceStatus
    }
}

private extension EvidenceInstructionsPresenter {
    func validateDeviceStatus(onSuccess: @escaping () -> Void) {
        guard let deviceStatus else {
            onSuccess()
            return
        }
        if deviceStatus.isLowStorageStatus {
            wireframe.showLowStorage(from: view, onProceed: onSuccess)
        } else if deviceStatus.isLowBatteryStatus {
            wireframe.showLowBattery(from: view, onProceed: onSuccess)
        } else {
            onSuccess()
        }
    }

    func proceedAndClose() {
        wireframe.close(view: view) { [model] in
            model.onProceed()
        }
    }
}
