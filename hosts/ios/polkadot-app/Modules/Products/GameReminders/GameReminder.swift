import Foundation
import Products

/// Offsets around a product's game start that the host applies. They are host UI and never travel on the wire.
enum GameReminderTiming {
    /// How long before the start the alarm, or its fallback notification, fires.
    static let alarmLeadTime: TimeInterval = 20
    /// How long before the start the countdown pill is shown.
    static let pillLeadTime: TimeInterval = 3 * 60
    /// How long after the start the reminder is kept, so a returning player still lands in the game.
    static let openWindow: TimeInterval = 60 * 60
}

/// How the OS was asked to reach the user for one reminder.
enum GameReminderDelivery: Codable, Hashable, Sendable {
    /// An AlarmKit alarm with this id.
    case alarm(UUID)
    /// A pending local notification with this identifier.
    case notification(String)
}

/// The one reminder a product holds: when its next game starts and how the user will be reached.
struct GameReminder: Codable, Equatable, Sendable {
    let productId: ProductId
    let startsAt: Date
    var delivery: GameReminderDelivery?
    /// Set once the product has been opened after the start; leaving it afterwards drops the reminder.
    var openedAfterStart: Bool
}

/// Where a reminder is relative to its start.
enum GameReminderPhase: Equatable, Sendable {
    /// More than three minutes before the start.
    case pending
    /// In the last three minutes before the start.
    case imminent
    /// From the start until an hour after it.
    case started
    /// An hour or more after the start.
    case expired

    static func of(_ reminder: GameReminder, at now: Date) -> GameReminderPhase {
        let untilStart = reminder.startsAt.timeIntervalSince(now)
        if untilStart > GameReminderTiming.pillLeadTime {
            return .pending
        }
        if untilStart > 0 {
            return .imminent
        }
        return -untilStart < GameReminderTiming.openWindow ? .started : .expired
    }
}
