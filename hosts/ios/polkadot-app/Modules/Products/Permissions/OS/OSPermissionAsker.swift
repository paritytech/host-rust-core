import AlarmKit
import AVFoundation
import EventKit
import Foundation
import Products

final class OSPermissionAsker: @unchecked Sendable {
    private let notificationService: UserNotificationServicing

    init(notificationService: UserNotificationServicing = UserNotificationService.shared) {
        self.notificationService = notificationService
    }
}

extension OSPermissionAsker: OSPermissionAsking {
    func checkPermission(for capability: DeviceCapabilityType) async -> OSPermissionStatus {
        switch capability {
        case .notifications:
            await checkNotificationStatus()
        case .alarm:
            checkAlarmStatus()
        case .calendar:
            checkCalendarStatus()
        case .camera:
            checkCaptureDeviceStatus(.video)
        case .microphone:
            checkCaptureDeviceStatus(.audio)
        case .bluetooth,
             .nfc,
             .location,
             .clipboard,
             .openUrl,
             .biometrics:
            // TODO: These capabilities require a native bridge to be usable from
            // the WKWebView sandbox. Return true for now; actual OS permission
            // prompts will be added when the bridge is implemented.
            .notDetermined
        }
    }

    func requestPermission(for capability: DeviceCapabilityType) async -> Bool {
        switch capability {
        case .notifications:
            await askNotifications()
        case .alarm:
            await askAlarm()
        case .calendar:
            await askCalendar()
        case .camera:
            await askCaptureDevice(.video)
        case .microphone:
            await askCaptureDevice(.audio)
        case .bluetooth,
             .nfc,
             .location,
             .clipboard,
             .openUrl,
             .biometrics:
            // TODO: These capabilities require a native bridge to be usable from
            // the WKWebView sandbox. Return true for now; actual OS permission
            // prompts will be added when the bridge is implemented.
            true
        }
    }
}

private extension OSPermissionAsker {
    func checkNotificationStatus() async -> OSPermissionStatus {
        let notificationStatus = await notificationService.notificationAccessStatus()
        return OSPermissionStatus(notificationStatus: notificationStatus)
    }

    func askNotifications() async -> Bool {
        await withCheckedContinuation { continuation in
            notificationService.requestNotificationsAuthorization { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// AlarmKit alone: below iOS 26.1 there is no alarm to ring, so the core falls back to notifications.
    func checkAlarmStatus() -> OSPermissionStatus {
        if #available(iOS 26.1, *) {
            return alarmAuthorizationStatus()
        }
        return .denied
    }

    func askAlarm() async -> Bool {
        guard #available(iOS 26.1, *) else {
            return false
        }
        switch alarmAuthorizationStatus() {
        case .allowed:
            return true
        case .notDetermined:
            return await (try? AlarmManager.shared.requestAuthorization()) == .authorized
        case .denied:
            return false
        }
    }

    @available(iOS 26.1, *)
    func alarmAuthorizationStatus() -> OSPermissionStatus {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            .allowed
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    func checkCalendarStatus() -> OSPermissionStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .writeOnly,
             .fullAccess:
            .allowed
        case .denied,
             .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    func askCalendar() async -> Bool {
        await (try? EKEventStore().requestWriteOnlyAccessToEvents()) ?? false
    }

    func askCaptureDevice(_ mediaType: AVMediaType) async -> Bool {
        await AVCaptureDevice.requestAccess(for: mediaType)
    }

    func checkCaptureDeviceStatus(_ mediaType: AVMediaType) -> OSPermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)

        return OSPermissionStatus(mediaStatus: status)
    }
}
