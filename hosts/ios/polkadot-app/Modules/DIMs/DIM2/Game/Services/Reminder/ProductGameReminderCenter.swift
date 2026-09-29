import AlarmKit
import EventKit
import Foundation
import Keystore_iOS
import Products
import UIKit

/// One game reminder slot for the whole host, driving the alarm, the countdown pill,
/// the calendar event and opening the product at the start. The holder may replace its reminder;
/// another product is busy until the holder cancels or the held start passes.
@MainActor
final class ProductGameReminderCenter: ProductGameReminderScheduling, ProductReminderHosting {
    struct Slot: Codable, Equatable {
        let productId: ProductId
        let startsAt: Date
        /// False delivers a notification even when AlarmKit is authorized.
        var ringAlarm = true
    }

    static let shared = ProductGameReminderCenter(
        alarm: makeAlarm(),
        notification: LocalNotificationGameReminder(
            localNotificationService: UserNotificationService.shared,
            settingsManager: SettingsManager.shared,
            keys: .product
        ),
        isAlarmAuthorized: { OSPermissionAsker.currentAlarmKitStatus() == .allowed },
        makeCalendar: { GameCalendarService(eventStore: EKEventStore()) },
        settingsManager: SettingsManager.shared,
        applicationState: { UIApplication.shared.applicationState },
        openProduct: { ProductOpener.open(productId: $0) },
        now: { Date() }
    )

    static let pillID = AppWidgetID("productGame")

    /// How late after the start a wake-up may run and still open the product.
    private static let openGrace: TimeInterval = 30

    /// Calendar events are added only for games at least this far away, as for the native game.
    private static let calendarLeadTime: TimeInterval = .secondsInHour
    private static let calendarEventDuration: TimeInterval = 30 * .secondsInMinute
    private static let calendarRemindBefore: TimeInterval = 5 * .secondsInMinute

    private let alarm: (any GameStartReminderServicing)?
    private let notification: any GameStartReminderServicing
    private let isAlarmAuthorized: () -> Bool
    /// Builds the calendar at add time, so its store sees the current grant.
    private let makeCalendar: () -> any GameCalendarServicing
    private let settingsManager: SettingsManagerProtocol
    private let applicationState: () -> UIApplication.State
    private let openProduct: (ProductId) -> Void
    private let now: () -> Date

    private weak var widgets: AppWidgetManaging?
    private var wakeUp: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?

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
        makeCalendar: @escaping () -> any GameCalendarServicing,
        settingsManager: SettingsManagerProtocol,
        applicationState: @escaping () -> UIApplication.State,
        openProduct: @escaping (ProductId) -> Void,
        now: @escaping () -> Date
    ) {
        self.alarm = alarm
        self.notification = notification
        self.isAlarmAuthorized = isAlarmAuthorized
        self.makeCalendar = makeCalendar
        self.settingsManager = settingsManager
        self.applicationState = applicationState
        self.openProduct = openProduct
        self.now = now
    }

    var slot: Slot? {
        guard let data = settingsManager.anyValue(for: SettingsKey.productGameReminder.rawValue) as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Slot.self, from: data)
    }

    func start(widgets: AppWidgetManaging) {
        self.widgets = widgets
        observeBecomingActive()
        refresh()
    }

    func schedule(
        productId: ProductId,
        startsAt: Date,
        ringAlarm: Bool,
        addCalendarEvent: Bool
    ) async -> ProductGameScheduleOutcome {
        if let current = slot, current.productId != productId, now() < current.startsAt {
            return .busy
        }

        let next = Slot(
            productId: productId,
            startsAt: Date(timeIntervalSince1970: startsAt.timeIntervalSince1970.rounded(.down)),
            ringAlarm: ringAlarm
        )
        deliver(next)
        refresh()

        if addCalendarEvent {
            await addCalendarEventIfNeeded(productId: productId, startsAt: next.startsAt)
        }
        return .scheduled
    }

    func cancel(productId: ProductId) {
        guard slot?.productId == productId else {
            return
        }
        drop()
        refresh()
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
            showPill(for: nil)
            let isLate = now.timeIntervalSince(slot.startsAt) >= Self.openGrace
            if applicationState() == .background, !isLate {
                // Becoming active within the grace opens the product.
                wake(at: slot.startsAt.addingTimeInterval(Self.openGrace), from: now)
                return
            }
            drop()
            if !isLate {
                openProduct(slot.productId)
            }
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

    func deliver(_ next: Slot) {
        let (delivery, unused): (any GameStartReminderServicing, (any GameStartReminderServicing)?) =
            if next.ringAlarm, let alarm, isAlarmAuthorized() { (alarm, notification) } else { (notification, alarm) }
        if let current = slot, current != next {
            // The delivered alarm or notification opens the product it was scheduled for.
            delivery.cancelReminder()
        }
        unused?.cancelReminder()
        store(next)

        delivery.scheduleReminder(
            gameDate: next.startsAt,
            target: .product(next.productId),
            timingSeconds: settingsManager.gameAlarmTimingSeconds
        )
    }

    /// Write-only: events are never removed, so a repeat for the same start adds nothing.
    func addCalendarEventIfNeeded(productId: ProductId, startsAt: Date) async {
        guard startsAt.timeIntervalSince(now()) >= Self.calendarLeadTime else {
            return
        }
        let startSeconds = Int(startsAt.timeIntervalSince1970)
        let calendar = makeCalendar()
        guard settingsManager.integer(for: .productGameCalendarStartsAt) != startSeconds,
              await calendar.requestWriteAccess() else {
            return
        }
        // The access prompt may outlive the reminder it was asked for.
        guard let slot, slot.productId == productId, slot.startsAt == startsAt else {
            return
        }

        let event = CalendarGameModel(
            title: String(localized: .Game.calendarEventGameTitle),
            startDate: startsAt,
            endDate: startsAt.addingTimeInterval(Self.calendarEventDuration),
            notes: nil,
            remindBefore: Self.calendarRemindBefore
        )
        do {
            try calendar.addEvent(for: event)
        } catch {
            Logger.shared.error("Failed to add product game to calendar: \(error)")
            return
        }
        settingsManager.set(value: startSeconds, for: .productGameCalendarStartsAt)
    }

    func drop() {
        store(nil)
        alarm?.cancelReminder()
        notification.cancelReminder()
    }

    func store(_ slot: Slot?) {
        guard let slot, let data = try? JSONEncoder().encode(slot) else {
            settingsManager.removeValue(for: .productGameReminder)
            return
        }
        settingsManager.set(anyValue: data, for: SettingsKey.productGameReminder.rawValue)
    }

    func showPill(for slot: Slot?) {
        guard let slot else {
            widgets?.detachWidget(for: Self.pillID)
            return
        }

        let configuration = GameRoomPillConfiguration(
            content: .waiting(gameDate: slot.startsAt)
        ) { [openProduct = self.openProduct] in
            openProduct(slot.productId)
        }
        widgets?.attachWidget(configuration, for: Self.pillID)
    }

    /// A wake-up timer can fire while the app is still resuming, so becoming active re-checks the start.
    func observeBecomingActive() {
        guard activeObserver == nil else {
            return
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
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
