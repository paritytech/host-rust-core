import Foundation
import EventCenter

protocol AppEventVisiting: EventVisitorProtocol {
    func processSelectedUsernameChanged(event: SelectedUsernameChanged)
    func processBackupStatusChanged(event: BackupStatusChanged)
    func processBalanceSyncState(event: BalanceSyncState)
    func processSelectedCurrencyChanged(event: SelectedCurrencyChanged)
}

extension AppEventVisiting {
    func processSelectedUsernameChanged(event _: SelectedUsernameChanged) {}
    func processBackupStatusChanged(event _: BackupStatusChanged) {}
    func processBalanceSyncState(event _: BalanceSyncState) {}
    func processSelectedCurrencyChanged(event _: SelectedCurrencyChanged) {}
}
