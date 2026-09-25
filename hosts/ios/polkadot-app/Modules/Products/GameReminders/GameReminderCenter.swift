import Foundation
import Products

/// What a TrUAPI product's game reminder calls reach.
protocol GameReminderScheduling: Sendable {
    /// Hold `startsAt` as the product's reminder, replacing any it holds.
    func schedule(productId: ProductId, startsAt: Date) async
    /// Drop the product's reminder. Dropping none succeeds.
    func cancel(productId: ProductId) async
}

/// What the game reminder opener and pill observe and drive on ``GameReminderCenter``.
protocol GameReminderObserving: Sendable {
    /// The current reminders, then the whole set again after every change.
    func changes() async -> AsyncStream<[GameReminder]>
    /// Record that the player is in the product after its start.
    func markOpened(productId: ProductId) async
    /// The player left the product; drops a reminder already opened after its start.
    func productLeft(productId: ProductId) async
    /// Withdraw the scheduled alarm or notification, keeping the reminder.
    func suppressAlarm(productId: ProductId) async
}

/// Holds the one game reminder each product may have, persists it across app kill and reboot, and asks the OS
/// to reach the user twenty seconds before the start.
///
/// Operations run one after another, so two schedules for the same product can never leave an alarm the store
/// no longer knows about.
actor GameReminderCenter: GameReminderScheduling {
    static let shared = GameReminderCenter()

    private let store: GameReminderStoring
    private let delivery: GameReminderDelivering
    private let now: @Sendable () -> Date
    private let logger: LoggerProtocol
    private var tail: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<[GameReminder]>.Continuation] = [:]

    init(
        store: GameReminderStoring = UserDefaultsGameReminderStore(),
        delivery: GameReminderDelivering = SystemGameReminderDelivery(),
        now: @escaping @Sendable () -> Date = { Date() },
        logger: LoggerProtocol = Logger.shared
    ) {
        self.store = store
        self.delivery = delivery
        self.now = now
        self.logger = logger
    }

    func schedule(productId: ProductId, startsAt: Date) async {
        await serialized { center in
            await center.performSchedule(productId: productId, startsAt: startsAt)
        }
    }

    func cancel(productId: ProductId) async {
        await serialized { center in
            await center.performCancel(productId: productId)
        }
    }

    /// Drop reminders an hour or more past their start. Alarms and notifications themselves outlive a reboot on
    /// iOS, so nothing needs re-registering.
    func restoreAll() async {
        await serialized { center in
            await center.performRestore()
        }
    }

    /// The last state persisted for the product. This reads the store directly and is not serialized against
    /// in-flight `schedule`, `cancel`, or `restoreAll` calls.
    func reminder(for productId: ProductId) -> GameReminder? {
        store.load()[productId]
    }

    func changes() -> AsyncStream<[GameReminder]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[GameReminder]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(Array(store.load().values))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    func markOpened(productId: ProductId) async {
        await serialized { center in
            await center.performMarkOpened(productId: productId)
        }
    }

    func productLeft(productId: ProductId) async {
        await serialized { center in
            await center.performProductLeft(productId: productId)
        }
    }

    func suppressAlarm(productId: ProductId) async {
        await serialized { center in
            await center.performSuppressAlarm(productId: productId)
        }
    }
}

private extension GameReminderCenter {
    /// Chains `operation` onto the tail of previously serialized operations so schedules and cancellations for
    /// the same product never interleave. `operation` must call a `perform*` method directly; it must never await
    /// `schedule`, `cancel`, or `restoreAll`, which would enqueue behind this call's own tail and wait forever.
    func serialized(_ operation: @escaping @Sendable (GameReminderCenter) async -> Void) async {
        let previous = tail
        let task = Task { [self] in
            await previous?.value
            await operation(self)
        }
        tail = task
        await task.value
    }

    func performSchedule(productId: ProductId, startsAt: Date) async {
        if let previous = store.load()[productId]?.delivery {
            await delivery.withdraw(previous)
        }

        let fireDate = startsAt.addingTimeInterval(-GameReminderTiming.alarmLeadTime)
        let scheduled = fireDate > now()
            ? await delivery.deliver(productId: productId, firingAt: fireDate)
            : nil

        var reminders = store.load()
        reminders[productId] = GameReminder(
            productId: productId,
            startsAt: startsAt,
            delivery: scheduled,
            openedAfterStart: false
        )
        store.save(reminders)
        logger.debug("Game reminder held for \(productId) at \(startsAt)")
        publish()
    }

    func performCancel(productId: ProductId) async {
        var reminders = store.load()
        guard let removed = reminders.removeValue(forKey: productId) else {
            return
        }
        if let scheduled = removed.delivery {
            await delivery.withdraw(scheduled)
        }
        store.save(reminders)
        logger.debug("Game reminder dropped for \(productId)")
        publish()
    }

    func performRestore() async {
        let date = now()
        var reminders = store.load()
        let expired = reminders.values.filter { GameReminderPhase.of($0, at: date) == .expired }
        guard !expired.isEmpty else {
            return
        }
        for reminder in expired {
            if let scheduled = reminder.delivery {
                await delivery.withdraw(scheduled)
            }
            reminders.removeValue(forKey: reminder.productId)
        }
        store.save(reminders)
        publish()
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func publish() {
        let current = Array(store.load().values)
        observers.values.forEach { $0.yield(current) }
    }

    func performMarkOpened(productId: ProductId) async {
        var reminders = store.load()
        guard var reminder = reminders[productId],
              !reminder.openedAfterStart,
              GameReminderPhase.of(reminder, at: now()) == .started else {
            return
        }
        reminder.openedAfterStart = true
        reminders[productId] = reminder
        store.save(reminders)
        publish()
    }

    func performProductLeft(productId: ProductId) async {
        var reminders = store.load()
        guard let reminder = reminders[productId], reminder.openedAfterStart else {
            return
        }
        reminders.removeValue(forKey: productId)
        if let scheduled = reminder.delivery {
            await delivery.withdraw(scheduled)
        }
        store.save(reminders)
        publish()
    }

    func performSuppressAlarm(productId: ProductId) async {
        var reminders = store.load()
        guard var reminder = reminders[productId], let scheduled = reminder.delivery else {
            return
        }
        await delivery.withdraw(scheduled)
        reminder.delivery = nil
        reminders[productId] = reminder
        store.save(reminders)
        publish()
    }
}

extension GameReminderCenter: GameReminderObserving {}
