import Foundation

/// When the game reminder opener and pill next need to look at the clock.
enum GameReminderSchedule {
    /// Margin before the alarm's fire time within which a visible product silences it.
    static let alarmSuppressionMargin: TimeInterval = 2

    /// The first instant after `now` at which some reminder changes phase: the pill appears, the alarm is about to
    /// fire, the game starts, or the hour after the start ends.
    static func nextBoundary(after now: Date, reminders: [GameReminder]) -> Date? {
        reminders
            .flatMap { reminder in
                [
                    reminder.startsAt.addingTimeInterval(-GameReminderTiming.pillLeadTime),
                    reminder.startsAt.addingTimeInterval(-(GameReminderTiming.alarmLeadTime + alarmSuppressionMargin)),
                    reminder.startsAt,
                    reminder.startsAt.addingTimeInterval(GameReminderTiming.openWindow)
                ]
            }
            .filter { $0 > now }
            .min()
    }
}
