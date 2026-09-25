import Foundation
import PolkadotUI
import Products

/// Shows the "Game starts in" countdown pill in the tab bar's floating widget stack for each product in the last
/// three minutes before its game, except while that product is on screen.
@MainActor
final class GameReminderPillPresenter {
    private let reminders: GameReminderObserving
    private let visibility: ProductVisibilityReporting
    private weak var widgets: AppWidgetManaging?
    private let now: () -> Date
    private let onTap: @MainActor (ProductId) -> Void

    private var current: [GameReminder] = []
    private var shown: [ProductId: Date] = [:]
    // Marked nonisolated(unsafe) so deinit, which is nonisolated, can cancel outstanding tasks; deinit only runs
    // once the last strong reference is gone, so no MainActor code can be concurrently touching these.
    private nonisolated(unsafe) var tasks: [Task<Void, Never>] = []
    private nonisolated(unsafe) var wakeTask: Task<Void, Never>?

    init(
        reminders: GameReminderObserving,
        visibility: ProductVisibilityReporting,
        widgets: AppWidgetManaging,
        now: @escaping () -> Date = { Date() },
        onTap: @escaping @MainActor (ProductId) -> Void
    ) {
        self.reminders = reminders
        self.visibility = visibility
        self.widgets = widgets
        self.now = now
        self.onTap = onTap
    }

    static func widgetId(for productId: ProductId) -> AppWidgetID {
        AppWidgetID("gameReminder:\(productId)")
    }

    func start() {
        guard tasks.isEmpty else {
            return
        }
        tasks = [
            Task { [weak self, reminders] in
                for await list in await reminders.changes() {
                    self?.handle(reminders: list)
                }
            },
            Task { [weak self, visibility] in
                for await value in visibility.changes() {
                    self?.handle(visibility: value)
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

    func handle(reminders list: [GameReminder]) {
        current = list
        render()
        armWake()
    }

    func handle(visibility _: ProductVisibility) {
        render()
    }
}

private extension GameReminderPillPresenter {
    func render() {
        let date = now()
        let visibleProduct = visibility.current.productId
        var wanted: [ProductId: Date] = [:]
        for reminder in current
            where GameReminderPhase.of(reminder, at: date) == .imminent && reminder.productId != visibleProduct {
            wanted[reminder.productId] = reminder.startsAt
        }

        for productId in shown.keys where wanted[productId] == nil {
            widgets?.detachWidget(for: Self.widgetId(for: productId))
        }
        for (productId, startsAt) in wanted where shown[productId] != startsAt {
            let onTap = onTap
            let configuration = GameRoomPillConfiguration(
                content: .waiting(gameDate: startsAt),
                onTap: {
                    Task { @MainActor in onTap(productId) }
                }
            )
            widgets?.attachWidget(configuration, for: Self.widgetId(for: productId))
        }
        shown = wanted
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
            render()
            armWake()
        }
    }
}
