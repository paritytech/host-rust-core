import Foundation

extension TimeInterval {
    func localizedDaysOrTime(for locale: Locale) -> String? {
        let days = daysFromSeconds

        if days > 0 {
            let daysString = String(localized: .Tattoo.daysFormat(value: Int(days)))
            return daysString
        } else {
            let formatter = DateComponentsFormatter.fullTime
            return formatter.value(for: locale).string(from: self)
        }
    }

    func localizedMinuteSeconds(for locale: Locale) -> String? {
        let formatter = DateComponentsFormatter.minuteSeconds
        return formatter.value(for: locale).string(from: self)
    }
}
