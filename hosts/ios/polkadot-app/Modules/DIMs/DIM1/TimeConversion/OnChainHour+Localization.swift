import Foundation
import Individuality

extension OnChainHour {
    func shortDisplayFromHours() -> String {
        let hoursInDay: UInt32 = 24
        let daysInWeek: UInt32 = 7
        let hoursInWeek = hoursInDay * daysInWeek

        if self % hoursInWeek == 0 {
            return String(
                localized: .Time.shortWeek(Int(self / hoursInWeek))
            )
        } else if self % hoursInDay == 0, (self / hoursInDay) > 1 {
            return String(
                localized: .Time.shortDay(Int(self / hoursInDay))
            )
        } else {
            return String(
                localized: .Time.shortHour(Int(self))
            )
        }
    }

    func longDisplayFromHours() -> String {
        let hoursInDay: UInt32 = 24
        let daysInWeek: UInt32 = 7
        let hoursInWeek = hoursInDay * daysInWeek

        if self % hoursInWeek == 0 {
            return String(
                localized: .Time.commonWeeks(value: Int(self / hoursInWeek))
            )
        } else if self % hoursInDay == 0, (self / hoursInDay) >= 1 {
            return String(
                localized: .Time.commonDays(value: Int(self / hoursInDay))
            )
        } else {
            return String(
                localized: .Time.commonHours(value: Int(self))
            )
        }
    }
}
