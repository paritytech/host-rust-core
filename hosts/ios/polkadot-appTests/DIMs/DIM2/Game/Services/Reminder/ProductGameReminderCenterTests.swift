import Foundation
import Testing
import UIKit
import Keystore_iOS
import PolkadotUI
@testable import polkadot_app

@MainActor
@Suite("Product game reminder center")
struct ProductGameReminderCenterTests {
    private let productId = "game.dot"
    private let startsAt = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeSUT(
        now: Date,
        alarmAuthorized: Bool = true,
        settings: SettingsManagerProtocol = InMemorySettingsManager()
    ) -> (center: ProductGameReminderCenter, fakes: Fakes) {
        let fakes = Fakes(now: now)
        fakes.alarmAuthorized = alarmAuthorized
        let center = ProductGameReminderCenter(
            alarm: fakes.alarm,
            notification: fakes.notification,
            isAlarmAuthorized: { fakes.alarmAuthorized },
            makeCalendar: { fakes.calendar },
            settingsManager: settings,
            applicationState: { fakes.applicationState },
            openProduct: { fakes.opened.append($0) },
            now: { fakes.now }
        )
        center.start(widgets: fakes.widgets)
        return (center, fakes)
    }

    @Test("A schedule rings an alarm at the native lead time when AlarmKit is authorized")
    func scheduleRingsAlarm() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600))

        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false)

        #expect(center.slot == .init(productId: productId, startsAt: startsAt))
        #expect(fakes.alarm.scheduled == [.init(gameDate: startsAt, target: .product(productId), timingSeconds: 20)])
        #expect(fakes.notification.scheduled.isEmpty)
    }

    @Test(
        "Without AlarmKit or without ringAlarm the reminder is a notification",
        arguments: [(true, false), (false, true)]
    )
    func scheduleFallsBackToNotification(ringAlarm: Bool, alarmAuthorized: Bool) async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600), alarmAuthorized: alarmAuthorized)

        _ = await center.schedule(
            productId: productId, startsAt: startsAt, ringAlarm: ringAlarm, addCalendarEvent: false
        )

        #expect(center.slot == .init(productId: productId, startsAt: startsAt, ringAlarm: ringAlarm))
        #expect(fakes.alarm.scheduled.isEmpty)
        #expect(
            fakes.notification.scheduled == [.init(gameDate: startsAt, target: .product(productId), timingSeconds: 20)]
        )
    }

    @Test("One slot: a repeat keeps the reminder, another product is busy, only the holder cancels it")
    func oneSlotForAllProducts() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600))

        #expect(await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false) == .scheduled)
        #expect(await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false) == .scheduled)
        #expect(fakes.alarm.cancelCount == 0)

        let alarm = (fakes.alarm.scheduled, fakes.alarm.cancelCount)
        let notification = (fakes.notification.scheduled, fakes.notification.cancelCount)
        #expect(await center.schedule(productId: "other.dot", startsAt: startsAt, addCalendarEvent: true) == .busy)
        #expect(center.slot == .init(productId: productId, startsAt: startsAt))
        #expect(fakes.alarm.scheduled == alarm.0 && fakes.alarm.cancelCount == alarm.1)
        #expect(fakes.notification.scheduled == notification.0 && fakes.notification.cancelCount == notification.1)
        #expect(fakes.calendar.added.isEmpty)

        center.cancel(productId: "other.dot")
        #expect(center.slot == .init(productId: productId, startsAt: startsAt))

        center.cancel(productId: productId)
        #expect(center.slot == nil)
        #expect(fakes.alarm.cancelCount == 1)
    }

    @Test("The holder replaces its own reminder with a new start")
    func holderReplacesOwnReminder() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600))
        let later = startsAt.addingTimeInterval(600)
        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false)

        #expect(await center.schedule(productId: productId, startsAt: later, addCalendarEvent: false) == .scheduled)

        #expect(center.slot == .init(productId: productId, startsAt: later))
        #expect(fakes.alarm.cancelCount == 1)
        #expect(fakes.alarm.scheduled.last == .init(gameDate: later, target: .product(productId), timingSeconds: 20))
    }

    @Test("Once the held start passes, another product takes the slot")
    func slotFreeAfterStart() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600))
        let next = startsAt.addingTimeInterval(7 * 24 * 3600)
        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false)

        fakes.now = startsAt.addingTimeInterval(60)

        #expect(await center.schedule(productId: "other.dot", startsAt: next, addCalendarEvent: false) == .scheduled)
        #expect(center.slot == .init(productId: "other.dot", startsAt: next))
        #expect(fakes.alarm.scheduled.last == .init(gameDate: next, target: .product("other.dot"), timingSeconds: 20))
    }

    @Test("With the calendar flag and a start exactly an hour away, one calendar event is added")
    func addsCalendarEventOnce() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600))

        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: true)
        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: true)

        let expected = RecordingCalendar.Event(
            title: String(localized: .Game.calendarEventGameTitle),
            startDate: startsAt,
            endDate: startsAt.addingTimeInterval(1800),
            remindBefore: 300
        )
        #expect(fakes.calendar.added == [expected])
    }

    @Test(
        "No calendar event without the flag, for a start under an hour away, or without write access",
        arguments: [(false, 7200.0, true), (true, 3599.0, true), (true, 7200.0, false)]
    )
    func noCalendarEvent(addCalendarEvent: Bool, secondsBeforeStart: TimeInterval, writeAccess: Bool) async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-secondsBeforeStart))
        fakes.calendar.writeAccess = writeAccess

        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: addCalendarEvent)

        #expect(fakes.calendar.added.isEmpty)
        #expect(center.slot == .init(productId: productId, startsAt: startsAt))
    }

    @Test(
        "Once an alarm can ring, rescheduling the same slot drops its notification",
        arguments: [(false, true), (true, false)]
    )
    func alarmReplacesNotification(firstRingAlarm: Bool, firstAlarmAuthorized: Bool) async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-3600), alarmAuthorized: firstAlarmAuthorized)
        _ = await center.schedule(
            productId: productId, startsAt: startsAt, ringAlarm: firstRingAlarm, addCalendarEvent: false
        )
        let notificationCancels = fakes.notification.cancelCount

        fakes.alarmAuthorized = true
        _ = await center.schedule(productId: productId, startsAt: startsAt, ringAlarm: true, addCalendarEvent: false)

        #expect(center.slot == .init(productId: productId, startsAt: startsAt, ringAlarm: true))
        #expect(fakes.notification.cancelCount == notificationCancels + 1)
        #expect(fakes.alarm.scheduled == [.init(gameDate: startsAt, target: .product(productId), timingSeconds: 20)])
    }

    @Test("The countdown pill shows only in the last five minutes")
    func pillInLastFiveMinutes() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-6 * 60))
        let pillID = ProductGameReminderCenter.pillID

        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false)
        #expect(fakes.widgets.attached.isEmpty)

        fakes.now = startsAt.addingTimeInterval(-4 * 60)
        center.refresh()
        #expect(fakes.widgets.attached[pillID]?.content == .waiting(gameDate: startsAt))

        center.cancel(productId: productId)
        #expect(fakes.widgets.attached.isEmpty)
    }

    @Test("The pill is hidden while its product is mounted and shown again after")
    func pillHiddenWhileMounted() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60))
        let pillID = ProductGameReminderCenter.pillID
        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false)
        #expect(fakes.widgets.attached[pillID] != nil)

        center.mountedProductId = productId
        #expect(fakes.widgets.attached.isEmpty)

        center.mountedProductId = "other.dot"
        #expect(fakes.widgets.attached[pillID] != nil)
    }

    @Test(
        "At the start the product opens in the foreground, long after it nothing opens, and the slot is dropped",
        arguments: [
            (UIApplication.State.active, 1.0, true),
            (.inactive, 1.0, true),
            (.active, 600.0, false),
            (.background, 600.0, false),
        ]
    )
    func opensAtStart(state: UIApplication.State, secondsAfterStart: TimeInterval, opens: Bool) async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60))
        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false)

        fakes.applicationState = state
        fakes.now = startsAt.addingTimeInterval(secondsAfterStart)
        center.refresh()

        #expect(fakes.opened == (opens ? [productId] : []))
        #expect(center.slot == nil)
        #expect(fakes.widgets.attached.isEmpty)
    }

    @Test("Reached in the background, the start keeps the slot and opens once the app is active within the grace")
    func opensWhenActiveAfterBackgroundStart() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60))
        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: false)

        fakes.applicationState = .background
        fakes.now = startsAt.addingTimeInterval(1)
        center.refresh()
        #expect(fakes.opened.isEmpty)
        #expect(center.slot == .init(productId: productId, startsAt: startsAt))
        #expect(fakes.widgets.attached.isEmpty)

        fakes.applicationState = .active
        fakes.now = startsAt.addingTimeInterval(5)
        center.refresh()
        #expect(fakes.opened == [productId])
        #expect(center.slot == nil)
    }

    @Test("The slot, including ringAlarm, survives a relaunch and its pill comes back")
    func restoresAfterRelaunch() async {
        let settings = InMemorySettingsManager()
        let (first, _) = makeSUT(now: startsAt.addingTimeInterval(-3600), settings: settings)
        _ = await first.schedule(productId: productId, startsAt: startsAt, ringAlarm: false, addCalendarEvent: false)

        let (relaunched, fakes) = makeSUT(now: startsAt.addingTimeInterval(-60), settings: settings)

        #expect(relaunched.slot == .init(productId: productId, startsAt: startsAt, ringAlarm: false))
        #expect(fakes.widgets.attached[ProductGameReminderCenter.pillID] != nil)
    }

    @Test("A cancel while calendar access is being asked adds no event")
    func cancelDuringCalendarAccessAddsNoEvent() async {
        let (center, fakes) = makeSUT(now: startsAt.addingTimeInterval(-7200))
        fakes.calendar.onRequestWriteAccess = { [productId] in center.cancel(productId: productId) }

        _ = await center.schedule(productId: productId, startsAt: startsAt, addCalendarEvent: true)

        #expect(center.slot == nil)
        #expect(fakes.calendar.added.isEmpty)
    }
}

private extension ProductGameReminderCenter {
    func schedule(productId: String, startsAt: Date, addCalendarEvent: Bool) async -> ProductGameScheduleOutcome {
        await schedule(productId: productId, startsAt: startsAt, ringAlarm: true, addCalendarEvent: addCalendarEvent)
    }
}

// MARK: - Fakes

private final class Fakes {
    var now: Date
    var applicationState: UIApplication.State = .active
    var alarmAuthorized = true
    var opened: [String] = []
    let alarm = RecordingGameReminder()
    let notification = RecordingGameReminder()
    let widgets = RecordingWidgets()
    let calendar = RecordingCalendar()

    init(now: Date) {
        self.now = now
    }
}

private final class RecordingGameReminder: GameStartReminderServicing {
    struct Call: Equatable {
        let gameDate: Date
        let target: GameReminderTarget
        let timingSeconds: Int
    }

    private(set) var scheduled: [Call] = []
    private(set) var cancelCount = 0

    func scheduleReminder(gameDate: Date, target: GameReminderTarget, timingSeconds: Int) {
        scheduled.append(Call(gameDate: gameDate, target: target, timingSeconds: timingSeconds))
    }

    func cancelReminder() {
        cancelCount += 1
    }
}

private final class RecordingWidgets: AppWidgetManaging {
    private(set) var attached: [AppWidgetID: GameRoomPillConfiguration] = [:]

    func attachWidget(_ configuration: any HashableContentConfiguration, for id: AppWidgetID) {
        attached[id] = configuration as? GameRoomPillConfiguration
    }

    func detachWidget(for id: AppWidgetID) {
        attached[id] = nil
    }
}

private final class RecordingCalendar: GameCalendarServicing {
    struct Event: Equatable {
        let title: String
        let startDate: Date
        let endDate: Date
        let remindBefore: TimeInterval?
    }

    var writeAccess = true
    var onRequestWriteAccess: (@MainActor () -> Void)?
    private(set) var added: [Event] = []

    func requestWriteAccess() async -> Bool {
        await onRequestWriteAccess?()
        return writeAccess
    }

    func addEvent(for game: CalendarGameModel) throws {
        added.append(
            Event(title: game.title, startDate: game.startDate, endDate: game.endDate, remindBefore: game.remindBefore)
        )
    }

    func savedReminder() -> GameCalendarReminder? {
        nil
    }

    func saveReminder(_ reminder: GameCalendarReminder) {}

    func clearReminder() {}
}
