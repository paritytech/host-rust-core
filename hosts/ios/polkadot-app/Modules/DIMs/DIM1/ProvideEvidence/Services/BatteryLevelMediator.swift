import UIKit

protocol BatteryMonitoring: AnyObject {
    var isBatteryMonitoringEnabled: Bool { get set }
    var batteryLevel: Float { get }
}

extension UIDevice: BatteryMonitoring {}

enum BatteryCheckError: Error {
    case unavailable
}

protocol BatteryLevelMediating: AnyObject {
    func checkBatteryLevel(_ requiredPercentage: Int) -> Result<Bool, BatteryCheckError>
    func stopMonitoring()
}

final class BatteryLevelMediator: BatteryLevelMediating {
    private enum Constants {
        static let batteryUnavailableThreshold: Float = 0.0
    }

    private let device: BatteryMonitoring

    init(device: BatteryMonitoring = UIDevice.current) {
        self.device = device
    }

    func checkBatteryLevel(_ requiredPercentage: Int) -> Result<Bool, BatteryCheckError> {
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = device.batteryLevel
        if batteryLevel < Constants.batteryUnavailableThreshold {
            return .failure(.unavailable)
        } else {
            let batteryPercentage = Int(batteryLevel * 100)
            return .success(batteryPercentage >= requiredPercentage)
        }
    }

    func stopMonitoring() {
        device.isBatteryMonitoringEnabled = false
    }
}
