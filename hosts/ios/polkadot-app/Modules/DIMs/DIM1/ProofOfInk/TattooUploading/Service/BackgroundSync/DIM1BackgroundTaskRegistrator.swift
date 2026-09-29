import BackgroundTasks

final class DIM1BackgroundTaskRegistrator {
    enum BackgroundTaskIds {
        static let stateRefresh = "io.novatech.determine.state.refresh"
    }

    static let shared = DIM1BackgroundTaskRegistrator()

    weak var service: DIM1BackgroundServiceProtocol? {
        didSet { handlePendingTaskIfNeeded() }
    }

    private var pendingTask: BGTask?

    private init() {}

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIds.stateRefresh,
            using: .main
        ) { [weak self] task in
            if let service = self?.service {
                service.fetchStateInBackground(asPartOf: task)
            } else {
                self?.pendingTask = task

                task.expirationHandler = {
                    self?.pendingTask?.setTaskCompleted(success: false)
                    self?.pendingTask = nil
                }
            }
        }
    }
}

private extension DIM1BackgroundTaskRegistrator {
    func handlePendingTaskIfNeeded() {
        guard let service,
              let pendingTask else {
            return
        }
        service.fetchStateInBackground(asPartOf: pendingTask)
        self.pendingTask = nil
    }
}
