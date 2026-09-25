import Foundation
import Testing

@testable import polkadot_app

@MainActor
@Suite("GameReminderOpener")
struct GameReminderOpenerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Clock { var date: Date; init(_ date: Date) { self.date = date } }

    private func reminder(
        _ id: String = "jollity.dot",
        startsAt: Date? = nil,
        opened: Bool = false,
        delivery: GameReminderDelivery? = nil
    ) -> GameReminder {
        GameReminder(productId: id, startsAt: startsAt ?? start, delivery: delivery, openedAfterStart: opened)
    }

    private final class Opened { var ids: [String] = [] }

    private func makeSUT(at date: Date) -> (GameReminderOpener, FakeGameReminderSource, FakeProductVisibility, Opened) {
        makeSUT(clock: Clock(date))
    }

    private func makeSUT(clock: Clock) -> (GameReminderOpener, FakeGameReminderSource, FakeProductVisibility, Opened) {
        let source = FakeGameReminderSource()
        let visibility = FakeProductVisibility()
        let opened = Opened()
        let sut = GameReminderOpener(
            reminders: source,
            visibility: visibility,
            now: { clock.date },
            open: { opened.ids.append($0) }
        )
        return (sut, source, visibility, opened)
    }

    @Test("a started reminder opens its product once while the app is active")
    func opensOnceAtStart() async {
        let (sut, _, _, opened) = makeSUT(at: start.addingTimeInterval(1))

        await sut.handle(reminders: [reminder()])
        await sut.handle(reminders: [reminder()])

        #expect(opened.ids == ["jollity.dot"])
    }

    @Test("nothing opens before the start, while inactive, or after the hour")
    func doesNotOpen() async {
        let (early, _, _, openedEarly) = makeSUT(at: start.addingTimeInterval(-1))
        await early.handle(reminders: [reminder()])
        #expect(openedEarly.ids.isEmpty)

        let (inactive, _, visibility, openedInactive) = makeSUT(at: start.addingTimeInterval(1))
        visibility.current = ProductVisibility(productId: nil, isAppActive: false)
        await inactive.handle(reminders: [reminder()])
        #expect(openedInactive.ids.isEmpty)

        let (late, _, _, openedLate) = makeSUT(at: start.addingTimeInterval(3600))
        await late.handle(reminders: [reminder()])
        #expect(openedLate.ids.isEmpty)
    }

    @Test("coming back to the foreground within the hour opens the product")
    func opensOnReturn() async {
        let (sut, _, visibility, opened) = makeSUT(at: start.addingTimeInterval(600))
        visibility.current = ProductVisibility(productId: nil, isAppActive: false)
        await sut.handle(reminders: [reminder()])
        #expect(opened.ids.isEmpty)

        visibility.current = ProductVisibility(productId: nil, isAppActive: true)
        await sut.handle(visibility: visibility.current)

        #expect(opened.ids == ["jollity.dot"])
    }

    @Test("a reminder already opened after the start is not opened again")
    func alreadyOpened() async {
        let (sut, _, _, opened) = makeSUT(at: start.addingTimeInterval(1))
        await sut.handle(reminders: [reminder(opened: true)])
        #expect(opened.ids.isEmpty)
    }

    @Test("being in the product after the start marks it opened without reopening it")
    func visibleMarksOpened() async {
        let (sut, source, visibility, opened) = makeSUT(at: start.addingTimeInterval(1))
        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)

        await sut.handle(reminders: [reminder()])

        #expect(opened.ids.isEmpty)
        #expect(source.marked == ["jollity.dot"])
    }

    @Test("leaving the product after being in it after the start drops the reminder")
    func leavingDrops() async {
        let (sut, source, visibility, _) = makeSUT(at: start.addingTimeInterval(1))
        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)
        await sut.handle(reminders: [reminder()])
        await sut.handle(visibility: visibility.current)

        visibility.current = ProductVisibility(productId: nil, isAppActive: true)
        await sut.handle(visibility: visibility.current)

        #expect(source.left == ["jollity.dot"])
    }

    @Test("leaving the product after the start does not reopen it while the drop is in flight")
    func leavingDoesNotReopen() async {
        let (sut, _, visibility, opened) = makeSUT(at: start.addingTimeInterval(1))
        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)
        await sut.handle(reminders: [reminder()])
        await sut.handle(visibility: visibility.current)

        visibility.current = ProductVisibility(productId: nil, isAppActive: true)
        await sut.handle(visibility: visibility.current)

        #expect(opened.ids.isEmpty)
    }

    @Test("leaving the product before the start keeps the reminder")
    func leavingBeforeStartKeeps() async {
        let (sut, source, visibility, _) = makeSUT(at: start.addingTimeInterval(-60))
        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)
        await sut.handle(reminders: [reminder()])
        await sut.handle(visibility: visibility.current)

        visibility.current = ProductVisibility(productId: nil, isAppActive: true)
        await sut.handle(visibility: visibility.current)

        #expect(source.left.isEmpty)
    }

    @Test("a product on screen just before the alarm silences it")
    func suppressesAlarm() async {
        let (sut, source, visibility, _) = makeSUT(at: start.addingTimeInterval(-21))
        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)

        await sut.handle(reminders: [reminder(delivery: .notification("game:jollity.dot"))])

        #expect(source.suppressed == ["jollity.dot"])
    }

    @Test("a product on screen earlier in the last minutes does not silence the alarm yet")
    func noEarlySuppression() async {
        let (sut, source, visibility, _) = makeSUT(at: start.addingTimeInterval(-60))
        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)

        await sut.handle(reminders: [reminder(delivery: .notification("game:jollity.dot"))])

        #expect(source.suppressed.isEmpty)
    }

    @Test("a rescheduled reminder opens again at its new start")
    func reschedulingReopens() async {
        let clock = Clock(start.addingTimeInterval(1))
        let (sut, _, _, opened) = makeSUT(clock: clock)

        await sut.handle(reminders: [reminder()])
        #expect(opened.ids == ["jollity.dot"])

        let newStart = start.addingTimeInterval(3600)
        clock.date = newStart.addingTimeInterval(1)
        await sut.handle(reminders: [reminder(startsAt: newStart)])

        #expect(opened.ids == ["jollity.dot", "jollity.dot"])
    }

    @Test("a rescheduled reminder is marked opened again when visible after its new start")
    func reschedulingMarksOpenedAgain() async {
        let clock = Clock(start.addingTimeInterval(1))
        let (sut, source, visibility, _) = makeSUT(clock: clock)
        visibility.current = ProductVisibility(productId: "jollity.dot", isAppActive: true)

        await sut.handle(reminders: [reminder()])
        #expect(source.marked == ["jollity.dot"])

        let newStart = start.addingTimeInterval(3600)
        clock.date = newStart.addingTimeInterval(1)
        await sut.handle(reminders: [reminder(startsAt: newStart)])

        #expect(source.marked == ["jollity.dot", "jollity.dot"])
    }

    @Test("releasing the opener after start cancels its tasks and stops observing")
    func releasingCancelsObserving() async {
        let source = FakeGameReminderSource()
        let visibility = FakeProductVisibility()
        var sut: GameReminderOpener? = GameReminderOpener(
            reminders: source,
            visibility: visibility,
            now: { Date() },
            open: { _ in }
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
