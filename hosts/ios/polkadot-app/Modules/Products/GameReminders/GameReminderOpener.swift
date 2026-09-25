import Foundation
import Products

/// Opens a product's SPA when its game starts, once, and keeps the reminder in step with whether the player is in
/// the product: marked opened while visible after the start, dropped when they leave it, and its alarm silenced when
/// the product is already on screen as the alarm is due.
@MainActor
final class GameReminderOpener {
    private let reminders: GameReminderObserving
    private let visibility: ProductVisibilityReporting
    private let now: () -> Date
    private let open: (ProductId) -> Void

    private var current: [GameReminder] = []
    private var requested: Set<ProductId> = []
    private var markedOpened: Set<ProductId> = []
    /// The last `startsAt` seen for each product, so a reschedule (same product, new start) can be told apart from
    /// an unchanged reminder and clear the stale `requested`/`markedOpened` membership it would otherwise keep.
    private var observedStart: [ProductId: Date] = [:]
    private var lastVisible: ProductId?
    // Marked nonisolated(unsafe) so deinit, which is nonisolated, can cancel outstanding tasks; deinit only runs
    // once the last strong reference is gone, so no MainActor code can be concurrently touching these.
    private nonisolated(unsafe) var tasks: [Task<Void, Never>] = []
    private nonisolated(unsafe) var wakeTask: Task<Void, Never>?

    init(
        reminders: GameReminderObserving,
        visibility: ProductVisibilityReporting,
        now: @escaping () -> Date = { Date() },
        open: @escaping (ProductId) -> Void
    ) {
        self.reminders = reminders
        self.visibility = visibility
        self.now = now
        self.open = open
    }

    func start() {
        guard tasks.isEmpty else {
            return
        }
        tasks = [
            Task { [weak self, reminders] in
                for await list in await reminders.changes() {
                    await self?.handle(reminders: list)
                }
            },
            Task { [weak self, visibility] in
                for await value in visibility.changes() {
                    await self?.handle(visibility: value)
                }
            }
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        wakeTask?.cancel()
        wakeTask = nil
    }

    deinit {
        tasks.forEach { $0.cancel() }
        wakeTask?.cancel()
    }

    func handle(reminders list: [GameReminder]) async {
        current = list
        let ids = Set(list.map(\.productId))
        for reminder in list where observedStart[reminder.productId] != reminder.startsAt {
            requested.remove(reminder.productId)
            markedOpened.remove(reminder.productId)
        }
        observedStart = Dictionary(uniqueKeysWithValues: list.map { ($0.productId, $0.startsAt) })
        requested.formIntersection(ids)
        markedOpened.formIntersection(ids)
        await evaluate()
        armWake()
    }

    func handle(visibility value: ProductVisibility) async {
        let previous = lastVisible
        lastVisible = value.productId
        // `markedOpened` keeps the product until the center's next change drops the reminder, so the evaluate
        // below cannot reopen the product the player has just left.
        if let previous, previous != value.productId, isOpenedAfterStart(previous) {
            await reminders.productLeft(productId: previous)
        }
        await evaluate()
    }
}

private extension GameReminderOpener {
    func isOpenedAfterStart(_ productId: ProductId) -> Bool {
        markedOpened.contains(productId)
            || current.contains { $0.productId == productId && $0.openedAfterStart }
    }

    func evaluate() async {
        let date = now()
        let state = visibility.current
        for reminder in current {
            let productId = reminder.productId
            switch GameReminderPhase.of(reminder, at: date) {
            case .started:
                if state.productId == productId {
                    if !isOpenedAfterStart(productId) {
                        markedOpened.insert(productId)
                        await reminders.markOpened(productId: productId)
                    }
                } else if state.isAppActive, !isOpenedAfterStart(productId), !requested.contains(productId) {
                    requested.insert(productId)
                    open(productId)
                }
            case .imminent:
                let untilStart = reminder.startsAt.timeIntervalSince(date)
                let window = GameReminderTiming.alarmLeadTime + GameReminderSchedule.alarmSuppressionMargin
                if state.productId == productId, reminder.delivery != nil, untilStart <= window {
                    await reminders.suppressAlarm(productId: productId)
                }
            case .pending, .expired:
                break
            }
        }
    }

    func armWake() {
        wakeTask?.cancel()
        guard let next = GameReminderSchedule.nextBoundary(after: now(), reminders: current) else {
            wakeTask = nil
            return
        }
        let delay = max(0, next.timeIntervalSince(now()))
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else {
                return
            }
            await evaluate()
            armWake()
        }
    }
}
