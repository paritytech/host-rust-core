import Foundation

struct GameConnectionDateStyle: FormatStyle {
    typealias FormatInput = Date
    typealias FormatOutput = String

    func format(_ value: Date) -> String {
        let locale = Locale.current

        let month = value.formatted(.dateTime.month(.wide).locale(locale))

        let day = Calendar.current.component(.day, from: value)
        let ordinalDay = NumberFormatter.ordinal.value(for: locale).string(from: NSNumber(value: day)) ?? "\(day)"
        return String(localized: .contactSourceDescriptionGame(ordinalDay: ordinalDay, month: month))
    }
}

extension FormatStyle where Self == GameConnectionDateStyle {
    static var gameConnectionInfo: GameConnectionDateStyle { .init() }
}
