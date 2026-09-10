import Foundation

public protocol GameDateFormatting {
    func format(date: Date) -> String
}

public final class GameDateFormatter: GameDateFormatting {
    private let numberFormatter: NumberFormatter
    private let calendar: Calendar
    private let locale: Locale
    private let timeOnNewLine: Bool

    public convenience init(
        locale: Locale = .current,
        calendar: Calendar = .current
    ) {
        self.init(locale: locale, calendar: calendar, timeOnNewLine: false)
    }

    public init(
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeOnNewLine: Bool
    ) {
        self.locale = locale
        self.calendar = calendar
        self.timeOnNewLine = timeOnNewLine

        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = locale
        numberFormatter = formatter
    }

    public func format(date: Date) -> String {
        let day = calendar.component(.day, from: date)
        let dayOrdinal = numberFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        let month = date.formatted(.dateTime.month(.abbreviated).locale(locale))
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        let timeString = timeOnNewLine ? "\n" + time : time

        return String(localized: .Game.gameStartFormat(month: month, date: dayOrdinal, time: timeString))
    }
}
