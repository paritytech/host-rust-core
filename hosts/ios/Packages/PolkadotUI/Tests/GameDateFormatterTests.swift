import Testing
import Foundation
import PolkadotUI

final class GameDateFormatterTests {
    private var calendar: Calendar!

    private var date: Date {
        let dateComponents = DateComponents(year: 2_023, month: 10, day: 2, hour: 14, minute: 30)
        return calendar.date(from: dateComponents)!
    }

    @Test("Format with US (imperial) Locale formats correctly")
    func formatWithUSLocale() {
        // Given
        let (formatter, calendar) = makeFormatter(localeIdentifier: "en_US")
        self.calendar = calendar

        // When
        let result = formatter.format(date: date)

        // Then
        // We verify that the formatted components are present in the result.
        // Since the final string depends on a localized format string we can't fully predict it,
        // but we expect "Oct", "2nd", and "2:30 PM" to be part of it.
        #expect(result.localizedCaseInsensitiveContains("Oct"), "Should contain abbreviated month")
        #expect(result.localizedCaseInsensitiveContains("2nd"), "Should contain ordinal day")
        #expect(result.contains("2:30") && result.contains("PM"), "Should contain time")
    }

    @Test("Format with UK (metric) Locale formats correctly")
    func formatWithUKLocale() {
        // Given
        let (formatter, calendar) = makeFormatter(localeIdentifier: "en_GB")
        self.calendar = calendar

        // When
        let result = formatter.format(date: date)

        // Then
        // Expect "Oct", "2nd", and "14:30"
        #expect(result.localizedCaseInsensitiveContains("Oct"), "Should contain abbreviated month")
        #expect(result.localizedCaseInsensitiveContains("2nd"), "Should contain ordinal day")
        #expect(result.contains("14:30"), "Should contain 24-hour time")
    }

    private func makeFormatter(localeIdentifier: String) -> (GameDateFormatter, Calendar) {
        let locale = Locale(identifier: localeIdentifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = GameDateFormatter(locale: locale, calendar: calendar)
        return (formatter, calendar)
    }
}
