import Foundation
import Testing

@testable import polkadot_app

@Suite("GameReminder")
struct GameReminderTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func reminder() -> GameReminder {
        GameReminder(productId: "jollity.dot", startsAt: start, delivery: nil, openedAfterStart: false)
    }

    @Test("phase follows the three-minute, start and one-hour boundaries")
    func phaseBoundaries() {
        let r = reminder()
        #expect(GameReminderPhase.of(r, at: start.addingTimeInterval(-180.001)) == .pending)
        #expect(GameReminderPhase.of(r, at: start.addingTimeInterval(-180)) == .imminent)
        #expect(GameReminderPhase.of(r, at: start.addingTimeInterval(-0.001)) == .imminent)
        #expect(GameReminderPhase.of(r, at: start) == .started)
        #expect(GameReminderPhase.of(r, at: start.addingTimeInterval(3599.999)) == .started)
        #expect(GameReminderPhase.of(r, at: start.addingTimeInterval(3600)) == .expired)
    }

    @Test("the store round-trips reminders and removes them all")
    func storeRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "GameReminderTests.\(UUID().uuidString)"))
        let store = UserDefaultsGameReminderStore(defaults: defaults)
        var saved = reminder()
        saved.delivery = .alarm(UUID())

        store.save([saved.productId: saved])
        #expect(UserDefaultsGameReminderStore(defaults: defaults).load() == [saved.productId: saved])

        store.removeAll()
        #expect(store.load().isEmpty)
    }

    @Test("a corrupt blob loads as empty")
    func corruptBlob() throws {
        let defaults = try #require(UserDefaults(suiteName: "GameReminderTests.\(UUID().uuidString)"))
        defaults.set(Data("not json".utf8), forKey: UserDefaultsGameReminderStore.defaultKey)
        #expect(UserDefaultsGameReminderStore(defaults: defaults).load().isEmpty)
    }
}
