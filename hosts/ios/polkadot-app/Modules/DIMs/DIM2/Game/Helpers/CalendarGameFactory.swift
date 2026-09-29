import Foundation

enum CalendarGameFactory {
    static func makeCalendarGame(for gameInfo: GameInfo) -> CalendarGameModel? {
        guard let start = gameInfo.gameDate,
              let end = gameInfo.reportingEndDate
        else { return nil }

        return CalendarGameModel(
            title: String(localized: .Game.calendarEventGameTitle),
            startDate: start,
            endDate: end,
            notes: nil,
            remindBefore: .secondsInMinute * 5
        )
    }
}
