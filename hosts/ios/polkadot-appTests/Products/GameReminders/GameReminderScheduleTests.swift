import Foundation
import Testing

@testable import polkadot_app

@Suite("GameReminderSchedule")
struct GameReminderScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func reminder(_ id: String, startsAt: Date) -> GameReminder {
        GameReminder(productId: id, startsAt: startsAt, delivery: nil, openedAfterStart: false)
    }

    @Test("the next boundary walks pill, alarm margin, start and the end of the hour")
    func boundaries() {
        let r = [reminder("a.dot", startsAt: start)]
        #expect(GameReminderSchedule.nextBoundary(after: start.addingTimeInterval(-600), reminders: r) == start.addingTimeInterval(-180))
        #expect(GameReminderSchedule.nextBoundary(after: start.addingTimeInterval(-180), reminders: r) == start.addingTimeInterval(-22))
        #expect(GameReminderSchedule.nextBoundary(after: start.addingTimeInterval(-22), reminders: r) == start)
        #expect(GameReminderSchedule.nextBoundary(after: start, reminders: r) == start.addingTimeInterval(3600))
        #expect(GameReminderSchedule.nextBoundary(after: start.addingTimeInterval(3600), reminders: r) == nil)
    }

    @Test("the earliest boundary across products wins")
    func earliest() {
        let r = [reminder("a.dot", startsAt: start), reminder("b.dot", startsAt: start.addingTimeInterval(-100))]
        #expect(GameReminderSchedule.nextBoundary(after: start.addingTimeInterval(-600), reminders: r) == start.addingTimeInterval(-280))
    }
}
