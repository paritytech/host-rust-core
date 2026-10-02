import AlarmKit
import EventKit
import Foundation
import Keystore_iOS
import Products
import UIKit

/// One game reminder per product, driving its alarm, the countdown pill, the calendar event
/// and opening the product at the start. A schedule replaces the reminder the same product holds.
@MainActor
final class ProductGameReminderCenter: ProductGameReminderScheduling, ProductReminderHosting {
    struct Slot: Codable, Equatable {
        let productId: ProductId
        let startsAt: Date
        /// False delivers a notification even when AlarmKit is authorized.
        var ringAlarm = true
        /// The start already in the calendar, so a repeat for it adds nothing.
        var calendarStartsAt: Date?
    }

    static let shared = ProductGameReminderCenter(
        makeAlarm: makeAlarm,
        makeNotification: {
            LocalNotificationGameReminder(
                localNotificationService: UserNotificationService.shared,
                settingsManager: SettingsManager.shared,
                keys: .product($0)
            )
        },
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

    fileprivate struct Reminders {
        let alarm: (any GameStartReminderServicing)?
        let notification: any GameStartReminderServicing
    }

    private let makeAlarm: (ProductId) -> (any GameStartReminderServicing)?
    private let makeNotification: (ProductId) -> any GameStartReminderServicing
    /// Builds the calendar at add time, so its store sees the current grant.
    private let makeCalendar: () -> any GameCalendarServicing
    private let settingsManager: SettingsManagerProtocol
    private let applicationState: () -> UIApplication.State
    private let openProduct: (ProductId) -> Void
    private let now: () -> Date

    /// One pair per product: AlarmKit serialises its calls per instance.
    private var reminders: [ProductId: Reminders] = [:]
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
        makeAlarm: @escaping (ProductId) -> (any GameStartReminderServicing)?,
        makeNotification: @escaping (ProductId) -> any GameStartReminderServicing,
        makeCalendar: @escaping () -> any GameCalendarServicing,
        settingsManager: SettingsManagerProtocol,
        applicationState: @escaping () -> UIApplication.State,
        openProduct: @escaping (ProductId) -> Void,
        now: @escaping () -> Date
    ) {
        self.makeAlarm = makeAlarm
        self.makeNotification = makeNotification
        self.makeCalendar = makeCalendar
        self.settingsManager = settingsManager
        self.applicationState = applicationState
        self.openProduct = openProduct
        self.now = now
    }

    /// Held reminders, soonest first.
    var slots: [Slot] {
        guard let data = settingsManager.anyValue(for: SettingsKey.productGameReminders.rawValue) as? Data,
              let slots = try? JSONDecoder().decode([Slot].self, from: data) else {
            return []
        }
        return slots.sorted { $0.startsAt < $1.startsAt }
    }

    func slot(for productId: ProductId) -> Slot? {
        slots.first { $0.productId == productId }
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
    ) async {
        let next = Slot(
            productId: productId,
            startsAt: Date(timeIntervalSince1970: startsAt.timeIntervalSince1970.rounded(.down)),
            ringAlarm: ringAlarm,
            calendarStartsAt: slot(for: productId)?.calendarStartsAt
        )
        deliver(next)
        refresh()

        if addCalendarEvent {
            await addCalendarEventIfNeeded(next)
        }
    }

    func cancel(productId: ProductId) {
        guard slot(for: productId) != nil else {
            return
        }
        drop(productId)
        refresh()
    }

    func refresh() {
        wakeUp?.cancel()
        wakeUp = nil

        let now = now()
        var pill: Slot?
        var wakeAt: Date?
        var opened = false

        for slot in slots {
            guard now < slot.startsAt else {
                let isLate = now.timeIntervalSince(slot.startsAt) >= Self.openGrace
                if applicationState() == .background, !isLate {
                    // Becoming active within the grace opens the product.
                    wakeAt = earliest(wakeAt, slot.startsAt.addingTimeInterval(Self.openGrace))
                    continue
                }
                drop(slot.productId)
                if !isLate, !opened {
                    opened = true
                    openProduct(slot.productId)
                }
                continue
            }

            let pillAt = slot.startsAt.addingTimeInterval(-GameRoomPillState.Constants.startingPillLeadTime)
            if pill == nil, now >= pillAt, slot.productId != mountedProductId {
                pill = slot
            }
            wakeAt = earliest(wakeAt, now < pillAt ? pillAt : slot.startsAt)
        }

        showPill(for: pill)
        if let wakeAt {
            wake(at: wakeAt, from: now)
        }
    }
}

private extension ProductGameReminderCenter {
    static func makeAlarm(for productId: ProductId) -> (any GameStartReminderServicing)? {
        if #available(iOS 26.1, *) {
            return AlarmKitGameReminder(
                alarmManger: .shared,
                settingsManager: SettingsManager.shared,
                keys: .product(productId)
            )
        }
        return nil
    }

    func reminders(for productId: ProductId) -> Reminders {
        if let reminders = reminders[productId] {
            return reminders
        }
        let reminders = Reminders(alarm: makeAlarm(productId), notification: makeNotification(productId))
        self.reminders[productId] = reminders
        return reminders
    }

    func deliver(_ next: Slot) {
        let reminders = reminders(for: next.productId)
        let (delivery, unused): (any GameStartReminderServicing, (any GameStartReminderServicing)?) =
            if next.ringAlarm, let alarm = reminders.alarm {
                (alarm, reminders.notification)
            } else {
                (reminders.notification, reminders.alarm)
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
    func addCalendarEventIfNeeded(_ slot: Slot) async {
        guard slot.startsAt.timeIntervalSince(now()) >= Self.calendarLeadTime,
              slot.calendarStartsAt != slot.startsAt else {
            return
        }
        let calendar = makeCalendar()
        guard await calendar.requestWriteAccess() else {
            return
        }
        // The access prompt may outlive the reminder it was asked for, or an overlapping schedule
        // may have added the event meanwhile.
        guard var held = self.slot(for: slot.productId),
              held.startsAt == slot.startsAt,
              held.calendarStartsAt != slot.startsAt else {
            return
        }

        let event = CalendarGameModel(
            title: String(localized: .Game.calendarEventGameTitle),
            startDate: slot.startsAt,
            endDate: slot.startsAt.addingTimeInterval(Self.calendarEventDuration),
            notes: nil,
            remindBefore: Self.calendarRemindBefore
        )
        do {
            try calendar.addEvent(for: event)
        } catch {
            Logger.shared.error("Failed to add product game to calendar: \(error)")
            return
        }
        held.calendarStartsAt = slot.startsAt
        store(held)
    }

    func drop(_ productId: ProductId) {
        store(slots.filter { $0.productId != productId })
        let reminders = reminders(for: productId)
        reminders.alarm?.cancelReminder()
        reminders.notification.cancelReminder()
    }

    func store(_ slot: Slot) {
        store(slots.filter { $0.productId != slot.productId } + [slot])
    }

    func store(_ slots: [Slot]) {
        guard !slots.isEmpty, let data = try? JSONEncoder().encode(slots) else {
            settingsManager.removeValue(for: .productGameReminders)
            return
        }
        settingsManager.set(anyValue: data, for: SettingsKey.productGameReminders.rawValue)
    }

    func earliest(_ current: Date?, _ candidate: Date) -> Date {
        current.map { min($0, candidate) } ?? candidate
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
