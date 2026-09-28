import AlarmKit
import Foundation
import Keystore_iOS
import Products
import UIKit

/// Temporary API: one game reminder slot shared by all products, driving the alarm, the countdown
/// pill and opening the product at the start.
@MainActor
final class ProductGameReminderCenter: ProductGameReminderScheduling {
    struct Slot: Equatable {
        let productId: ProductId
        let startsAt: Date
    }

    static let shared = ProductGameReminderCenter(
        alarm: makeAlarm(),
        notification: LocalNotificationGameReminder(
            localNotificationService: UserNotificationService.shared,
            settingsManager: SettingsManager.shared,
            keys: .product
        ),
        isAlarmAuthorized: { isAlarmKitAuthorized() },
        settingsManager: SettingsManager.shared,
        applicationState: { UIApplication.shared.applicationState },
        openProduct: { ProductOpener.open(productId: $0) },
        now: { Date() }
    )

    static func pillID(for productId: ProductId) -> AppWidgetID {
        AppWidgetID("productGame.\(productId)")
    }

    /// How late after the start a wake-up may run and still open the product.
    private static let openGrace: TimeInterval = 30

    private let alarm: (any GameStartReminderServicing)?
    private let notification: any GameStartReminderServicing
    private let isAlarmAuthorized: () -> Bool
    private let settingsManager: SettingsManagerProtocol
    private let applicationState: () -> UIApplication.State
    private let openProduct: (ProductId) -> Void
    private let now: () -> Date

    private weak var widgets: AppWidgetManaging?
    private var pillProductId: ProductId?
    private var wakeUp: Task<Void, Never>?

    /// The product whose SPA is mounted; its pill stays hidden.
    var mountedProductId: ProductId? {
        didSet {
            guard mountedProductId != oldValue else {
                return
            }
            refresh()
        }
    }

    init(
        alarm: (any GameStartReminderServicing)?,
        notification: any GameStartReminderServicing,
        isAlarmAuthorized: @escaping () -> Bool,
        settingsManager: SettingsManagerProtocol,
        applicationState: @escaping () -> UIApplication.State,
        openProduct: @escaping (ProductId) -> Void,
        now: @escaping () -> Date
    ) {
        self.alarm = alarm
        self.notification = notification
        self.isAlarmAuthorized = isAlarmAuthorized
        self.settingsManager = settingsManager
        self.applicationState = applicationState
        self.openProduct = openProduct
        self.now = now
    }

    var slot: Slot? {
        guard
            let productId = settingsManager.string(for: .productGameReminderProductId),
            let startsAt = settingsManager.integer(for: .productGameReminderStartsAt)
        else {
            return nil
        }
        return Slot(productId: productId, startsAt: Date(timeIntervalSince1970: TimeInterval(startsAt)))
    }

    func start(widgets: AppWidgetManaging) {
        self.widgets = widgets
        pillProductId = nil
        refresh()
    }

    func schedule(productId: ProductId, startsAt: Date) {
        let next = Slot(
            productId: productId,
            startsAt: Date(timeIntervalSince1970: startsAt.timeIntervalSince1970.rounded(.down))
        )
        let (delivery, unused): (any GameStartReminderServicing, (any GameStartReminderServicing)?) =
            if let alarm, isAlarmAuthorized() { (alarm, notification) } else { (notification, alarm) }
        if let current = slot, current != next {
            // The delivered alarm or notification opens the product it was scheduled for.
            delivery.cancelReminder()
        }
        unused?.cancelReminder()
        store(next)

        delivery.scheduleReminder(
            gameDate: next.startsAt,
            target: .product(productId),
            timingSeconds: settingsManager.gameAlarmTimingSeconds
        )

        refresh()
    }

    func cancel(productId: ProductId) {
        guard slot?.productId == productId else {
            return
        }
        clear()
    }

    func refresh() {
        wakeUp?.cancel()
        wakeUp = nil

        guard let slot else {
            showPill(for: nil)
            return
        }

        let now = now()

        guard now < slot.startsAt else {
            if applicationState() != .background, now.timeIntervalSince(slot.startsAt) < Self.openGrace {
                openProduct(slot.productId)
            }
            clear()
            return
        }

        let pillAt = slot.startsAt.addingTimeInterval(-GameRoomPillState.Constants.startingPillLeadTime)
        showPill(for: now >= pillAt && slot.productId != mountedProductId ? slot : nil)
        wake(at: now < pillAt ? pillAt : slot.startsAt, from: now)
    }
}

private extension ProductGameReminderCenter {
    static func makeAlarm() -> (any GameStartReminderServicing)? {
        if #available(iOS 26.1, *) {
            return AlarmKitGameReminder(alarmManger: .shared, settingsManager: SettingsManager.shared, keys: .product)
        }
        return nil
    }

    static func isAlarmKitAuthorized() -> Bool {
        if #available(iOS 26.1, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        return false
    }

    func clear() {
        store(nil)
        alarm?.cancelReminder()
        notification.cancelReminder()
        refresh()
    }

    func store(_ slot: Slot?) {
        guard let slot else {
            settingsManager.removeValue(for: .productGameReminderProductId)
            settingsManager.removeValue(for: .productGameReminderStartsAt)
            return
        }
        settingsManager.set(string: slot.productId, for: .productGameReminderProductId)
        settingsManager.set(value: Int(slot.startsAt.timeIntervalSince1970), for: .productGameReminderStartsAt)
    }

    func showPill(for slot: Slot?) {
        if let pillProductId, pillProductId != slot?.productId {
            widgets?.detachWidget(for: Self.pillID(for: pillProductId))
        }
        pillProductId = slot?.productId

        guard let slot else {
            return
        }

        let configuration = GameRoomPillConfiguration(
            content: .waiting(gameDate: slot.startsAt)
        ) { [openProduct = self.openProduct] in
            openProduct(slot.productId)
        }
        widgets?.attachWidget(configuration, for: Self.pillID(for: slot.productId))
    }

    func wake(at date: Date, from now: Date) {
        let delay = date.timeIntervalSince(now)
        wakeUp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            self?.refresh()
        }
    }
}
