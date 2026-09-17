import Foundation
import Keystore_iOS

enum SettingsKey: String {
    case username = "username.v2"
    case usernameClaimed = "usernameClaimed.v2"
    case isPerson = "isPerson.v2"
    case waitingRoomNotificationDate
    case gameStartNotificationDate
    case registrationStartNotificationDates
    case gameAboutToStartNotificationDate
    case registrationOpenNotificationDates
    case voucherInUseDismissed = "voucherInUseDismissed.v2"
    case playerTooltipShown
    case swipeTooltipShown
    case selectedCurrencyCode
    case fiatOnrampSessionIds
    case fiatOnrampTrackedTransactionIds
    case gameAlarmId
    case gameAlarmFireDate
    case gameAlarmTimingSeconds
    case coinageSyncNeeded = "coinageSyncNeeded.v2"
    // Balance restored notification
    case coinageBackupRestorePending = "coinageBackupRestorePending.v2"
    case coinScanHorizon = "coinScanHorizon.v2"
    case voucherScanHorizon = "voucherScanHorizon.v2"
    case deviceEncryptId = "deviceEncryptId.v2"
    case nextSyncUpdateId = "nextSyncUpdateId.v2"
    case themeSelected = "themeSelected.v2"
    case gameCalendarReminder
    case localNetworkPermissionRequested
    case backendSessionId = "backendSessionId.v2"
    case showTransferStrategyDebug
    case truApiRuntimeEnabled
    case coinageRecyclingStrategy
    #if TESTNET_FEATURE
        case tipsResetPending
    #endif
}

extension SettingsManagerProtocol {
    func integerArray(for setting: SettingsKey) -> [Int]? {
        anyValue(for: setting.rawValue) as? [Int]
    }

    func removeValue(for setting: SettingsKey) {
        removeValue(for: setting.rawValue)
    }

    func integer(for setting: SettingsKey) -> Int? {
        integer(for: setting.rawValue)
    }

    func set(value: Int, for setting: SettingsKey) {
        set(value: value, for: setting.rawValue)
    }

    func set(intArray: [Int], for setting: SettingsKey) {
        set(anyValue: intArray, for: setting.rawValue)
    }

    func set(value: Bool, for setting: SettingsKey) {
        set(value: value, for: setting.rawValue)
    }

    func value(for setting: SettingsKey) -> Bool {
        bool(for: setting.rawValue) ?? false
    }

    func set(string value: String, for key: SettingsKey) {
        set(anyValue: value, for: key.rawValue)
    }

    func string(for key: SettingsKey) -> String? {
        anyValue(for: key.rawValue) as? String
    }
}
