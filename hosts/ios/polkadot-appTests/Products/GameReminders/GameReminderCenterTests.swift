import Foundation
import Testing

@testable import polkadot_app

@Suite("GameReminderCenter")
struct GameReminderCenterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() throws -> UserDefaultsGameReminderStore {
        let defaults = try #require(UserDefaults(suiteName: "GameReminderCenterTests.\(UUID().uuidString)"))
        return UserDefaultsGameReminderStore(defaults: defaults)
    }

    private func makeCenter(
        store: GameReminderStoring,
        delivery: MockGameReminderDelivery
    ) -> GameReminderCenter {
        let fixed = now
        return GameReminderCenter(store: store, delivery: delivery, now: { fixed })
    }

    @Test("schedule delivers twenty seconds before the start and persists the reminder")
    func schedulePersists() async throws {
        let store = try makeStore()
        let delivery = MockGameReminderDelivery()
        let start = now.addingTimeInterval(600)

        await makeCenter(store: store, delivery: delivery).schedule(productId: "jollity.dot", startsAt: start)

        #expect(delivery.delivered.map(\.1) == [start.addingTimeInterval(-20)])
        let persisted = try #require(store.load()["jollity.dot"])
        #expect(persisted.startsAt == start)
        #expect(persisted.delivery == .notification("game:jollity.dot"))
        #expect(persisted.openedAfterStart == false)
    }

    @Test("a second schedule withdraws the first delivery and replaces the reminder")
    func scheduleReplaces() async throws {
        let store = try makeStore()
        let delivery = MockGameReminderDelivery()
        var count = 0
        delivery.result = { _ in count += 1; return .notification("n\(count)") }
        let center = makeCenter(store: store, delivery: delivery)

        await center.schedule(productId: "jollity.dot", startsAt: now.addingTimeInterval(600))
        await center.schedule(productId: "jollity.dot", startsAt: now.addingTimeInterval(900))

        #expect(delivery.withdrawn == [.notification("n1")])
        #expect(store.load()["jollity.dot"]?.startsAt == now.addingTimeInterval(900))
        #expect(store.load()["jollity.dot"]?.delivery == .notification("n2"))
    }

    @Test("two concurrent schedules for the same product withdraw exactly one delivery and keep the other")
    func concurrentSchedulesLeaveExactlyOneDeliveryWithdrawn() async throws {
        let store = try makeStore()
        let delivery = MockGameReminderDelivery()
        let counter = LockedCounter()
        delivery.result = { _ in .notification("n\(counter.next())") }
        let center = makeCenter(store: store, delivery: delivery)

        async let a: Void = center.schedule(productId: "jollity.dot", startsAt: now.addingTimeInterval(600))
        async let b: Void = center.schedule(productId: "jollity.dot", startsAt: now.addingTimeInterval(900))
        _ = await (a, b)

        let persisted = try #require(store.load()["jollity.dot"]?.delivery)
        #expect(delivery.withdrawn.count == 1)
        #expect(Set(delivery.withdrawn + [persisted]) == [.notification("n1"), .notification("n2")])
    }

    @Test("a start closer than the alarm lead keeps the reminder without a delivery")
    func startTooClose() async throws {
        let store = try makeStore()
        let delivery = MockGameReminderDelivery()

        await makeCenter(store: store, delivery: delivery).schedule(productId: "jollity.dot", startsAt: now.addingTimeInterval(10))

        #expect(delivery.delivered.isEmpty)
        #expect(store.load()["jollity.dot"]?.delivery == nil)
    }

    @Test("cancel withdraws and removes; cancelling nothing is a no-op")
    func cancel() async throws {
        let store = try makeStore()
        let delivery = MockGameReminderDelivery()
        let center = makeCenter(store: store, delivery: delivery)
        await center.schedule(productId: "jollity.dot", startsAt: now.addingTimeInterval(600))

        await center.cancel(productId: "jollity.dot")
        await center.cancel(productId: "jollity.dot")
        await center.cancel(productId: "other.dot")

        #expect(delivery.withdrawn == [.notification("game:jollity.dot")])
        #expect(store.load().isEmpty)
    }

    @Test("each product keeps its own reminder")
    func perProduct() async throws {
        let store = try makeStore()
        let center = makeCenter(store: store, delivery: MockGameReminderDelivery())

        await center.schedule(productId: "a.dot", startsAt: now.addingTimeInterval(600))
        await center.schedule(productId: "b.dot", startsAt: now.addingTimeInterval(700))
        await center.cancel(productId: "a.dot")

        #expect(Set(store.load().keys) == ["b.dot"])
    }

    @Test("restoreAll drops reminders an hour past their start and keeps the rest")
    func restoreDropsExpired() async throws {
        let store = try makeStore()
        let delivery = MockGameReminderDelivery()
        store.save([
            "old.dot": GameReminder(productId: "old.dot", startsAt: now.addingTimeInterval(-3600), delivery: .notification("old"), openedAfterStart: false),
            "live.dot": GameReminder(productId: "live.dot", startsAt: now.addingTimeInterval(-60), delivery: nil, openedAfterStart: false),
            "next.dot": GameReminder(productId: "next.dot", startsAt: now.addingTimeInterval(600), delivery: .notification("next"), openedAfterStart: false),
        ])

        await makeCenter(store: store, delivery: delivery).restoreAll()

        #expect(Set(store.load().keys) == ["live.dot", "next.dot"])
        #expect(delivery.withdrawn == [.notification("old")])
    }

    @Test("a new center on the same store sees the persisted reminder")
    func survivesRestart() async throws {
        let store = try makeStore()
        await makeCenter(store: store, delivery: MockGameReminderDelivery())
            .schedule(productId: "jollity.dot", startsAt: now.addingTimeInterval(600))

        let reloaded = await makeCenter(store: store, delivery: MockGameReminderDelivery()).reminder(for: "jollity.dot")

        #expect(reloaded?.startsAt == now.addingTimeInterval(600))
    }
}

/// A thread-safe increasing counter for tests that need distinct values across concurrently racing closures.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
