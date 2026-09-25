import Foundation
import Products

/// Persistence for the reminders the host holds, one per product.
protocol GameReminderStoring: Sendable {
    func load() -> [ProductId: GameReminder]
    func save(_ reminders: [ProductId: GameReminder])
    func removeAll()
}

/// Keeps every reminder as one JSON value in `UserDefaults`, so it survives app kill and reboot.
final class UserDefaultsGameReminderStore: GameReminderStoring, @unchecked Sendable {
    static let defaultKey = "truapi.gameReminders"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = UserDefaultsGameReminderStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [ProductId: GameReminder] {
        guard let data = defaults.data(forKey: key),
              let reminders = try? JSONDecoder().decode([ProductId: GameReminder].self, from: data) else {
            return [:]
        }
        return reminders
    }

    func save(_ reminders: [ProductId: GameReminder]) {
        guard !reminders.isEmpty else {
            removeAll()
            return
        }
        guard let data = try? JSONEncoder().encode(reminders) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }
}
