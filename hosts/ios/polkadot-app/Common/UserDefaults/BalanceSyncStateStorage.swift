import Foundation
import Keystore_iOS
import EventCenter

protocol BalanceSyncStateStoring: AnyObject {
    var isRestorePending: Bool { get set }
}

final class BalanceSyncStateStorage: BalanceSyncStateStoring {
    private let settingsManager: SettingsManagerProtocol
    private let eventCenter: EventCenterProtocol

    init(
        settingsManager: SettingsManagerProtocol = SettingsManager.shared,
        eventCenter: EventCenterProtocol = EventCenter.shared
    ) {
        self.settingsManager = settingsManager
        self.eventCenter = eventCenter
    }

    var isRestorePending: Bool {
        get {
            settingsManager.value(for: .coinageBackupRestorePending)
        }
        set {
            settingsManager.set(value: newValue, for: .coinageBackupRestorePending)
            eventCenter.notify(with: BalanceSyncState())
        }
    }
}
