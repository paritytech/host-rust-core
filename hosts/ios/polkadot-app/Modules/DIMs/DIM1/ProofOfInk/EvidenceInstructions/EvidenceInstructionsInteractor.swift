import UIKit

protocol EvidenceInstructionsInteractorInputProtocol: AnyObject {
    func updateDeviceStatus()
    func stopMonitoringDeviceStatus()
}

@MainActor
protocol EvidenceInstructionsInteractorOutputProtocol: AnyObject {
    func didUpdate(deviceStatus: ProvideEvidenceDeviceStatus)
}

final class EvidenceInstructionsInteractor {
    private enum Constants {
        static let requiredBatteryPercentage: Int = 50
        static let requiredSpaceInMB: Double = 100
    }

    weak var presenter: EvidenceInstructionsInteractorOutputProtocol?
    private let mode: EvidenceInstructionsMode
    private let batteryLevelMediator: BatteryLevelMediating
    private let storageSpaceMediator: StorageSpaceMediating

    init(
        mode: EvidenceInstructionsMode,
        batteryLevelMediator: BatteryLevelMediating,
        storageSpaceMediator: StorageSpaceMediating
    ) {
        self.mode = mode
        self.batteryLevelMediator = batteryLevelMediator
        self.storageSpaceMediator = storageSpaceMediator
    }
}

extension EvidenceInstructionsInteractor: EvidenceInstructionsInteractorInputProtocol {
    func updateDeviceStatus() {
        MainActor.assumeIsolated {
            presenter?.didUpdate(deviceStatus: provideDeviceCheck())
        }
    }

    func stopMonitoringDeviceStatus() {
        guard mode == .video else { return }
        batteryLevelMediator.stopMonitoring()
    }
}

private extension EvidenceInstructionsInteractor {
    func provideDeviceCheck() -> ProvideEvidenceDeviceStatus {
        guard mode == .video else {
            return .init(isLowBatteryStatus: false, isLowStorageStatus: false)
        }

        let isLowBatteryStatus: Bool
        let isLowStorageStatus: Bool

        switch batteryLevelMediator.checkBatteryLevel(Constants.requiredBatteryPercentage) {
        case let .success(isConditionSatisfied):
            isLowBatteryStatus = !isConditionSatisfied
        case .failure:
            isLowBatteryStatus = true
        }
        switch storageSpaceMediator.checkAvailableStorage(Constants.requiredSpaceInMB) {
        case let .success(isConditionSatisfied):
            isLowStorageStatus = !isConditionSatisfied
        case .failure:
            isLowStorageStatus = true
        }
        return .init(
            isLowBatteryStatus: isLowBatteryStatus,
            isLowStorageStatus: isLowStorageStatus
        )
    }
}
