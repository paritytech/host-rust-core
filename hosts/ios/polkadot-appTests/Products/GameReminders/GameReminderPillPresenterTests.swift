import Foundation
import Testing

@testable import polkadot_app

@MainActor
@Suite("GameReminderPillPresenter")
struct GameReminderPillPresenterTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Clock { var date: Date; init(_ date: Date) { self.date = date } }

    private func reminder(_ id: String = "jollity.dot", startsAt: Date? = nil) -> GameReminder {
        GameReminder(productId: id, startsAt: startsAt ?? start, delivery: nil, openedAfterStart: false)
    }

    private func makeSUT(clock: Clock) -> (GameReminderPillPresenter, FakeAppWidgets, FakeProductVisibility) {
        let widgets = FakeAppWidgets()
        let visibility = FakeProductVisibility()
        let sut = GameReminderPillPresenter(
            reminders: FakeGameReminderSource(),
            visibility: visibility,
            widgets: widgets,
            now: { clock.date },
            onTap: { _ in }
        )
        return (sut, widgets, visibility)
    }

    @Test("the pill shows for the last three minutes and goes at the start")
    func window() {
        let clock = Clock(start.addingTimeInterval(-181))
        let (sut, widgets, _) = makeSUT(clock: clock)
        let key = GameReminderPillPresenter.widgetId(for: "jollity.dot").rawValue

        sut.handle(reminders: [reminder()])
        #expect(widgets.attached[key] == nil)

        clock.date = start.addingTimeInterval(-180)
        sut.handle(reminders: [reminder()])
        let configuration = widgets.attached[key] as? GameRoomPillConfiguration
        #expect(configuration?.content == .waiting(gameDate: start))

        clock.date = start
        sut.handle(reminders: [reminder()])
        #expect(widgets.attached[key] == nil)
    }

    @Test("the pill hides while its product is on screen and comes back when the player leaves")
    func hiddenInProduct() {
        let clock = Clock(start.addingTimeInterval(-60))
        let (sut, widgets, visibility) = makeSUT(clock: clock)
        let key = GameReminderPillPresenter.widgetId(for: "jollity.dot").rawValue
        sut.handle(reminders: [reminder()])
        #expect(widgets.attached[key] != nil)

        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)
        sut.handle(visibility: visibility.current)
        #expect(widgets.attached[key] == nil)

        visibility.current = ProductVisibility(productId: "other.dot", isAppActive: true)
        sut.handle(visibility: visibility.current)
        #expect(widgets.attached[key] != nil)
    }

    @Test("one pill per product, and an unchanged pill is not re-attached")
    func perProduct() {
        let clock = Clock(start.addingTimeInterval(-60))
        let (sut, widgets, _) = makeSUT(clock: clock)

        sut.handle(reminders: [reminder("a.dot"), reminder("b.dot", startsAt: start.addingTimeInterval(30))])
        sut.handle(reminders: [reminder("a.dot"), reminder("b.dot", startsAt: start.addingTimeInterval(30))])

        #expect(Set(widgets.attached.keys) == [
            GameReminderPillPresenter.widgetId(for: "a.dot").rawValue,
            GameReminderPillPresenter.widgetId(for: "b.dot").rawValue
        ])
        #expect(widgets.attachCount == 2)
    }

    @Test("cancelling a reminder removes its pill")
    func cancelRemoves() {
        let clock = Clock(start.addingTimeInterval(-60))
        let (sut, widgets, _) = makeSUT(clock: clock)
        sut.handle(reminders: [reminder()])

        sut.handle(reminders: [])

        #expect(widgets.attached.isEmpty)
    }

    @Test("releasing the presenter after start cancels its tasks and stops observing")
    func releasingCancelsObserving() async {
        let source = FakeGameReminderSource()
        let widgets = FakeAppWidgets()
        let visibility = FakeProductVisibility()
        var sut: GameReminderPillPresenter? = GameReminderPillPresenter(
            reminders: source,
            visibility: visibility,
            widgets: widgets,
            now: { Date() },
            onTap: { _ in }
        )
        sut?.start()
        sut = nil

        var waited: TimeInterval = 0
        while !source.terminated, waited < 1 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 0.05
        }

        #expect(source.terminated)
    }
}
