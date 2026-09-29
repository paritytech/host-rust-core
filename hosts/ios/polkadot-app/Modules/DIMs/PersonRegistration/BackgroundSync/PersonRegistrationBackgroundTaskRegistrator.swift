import BackgroundTasks

final class PersonRegistrationBackgroundTaskRegistrator {
    enum BackgroundTaskIds {
        static let stateRefresh = "io.novatech.person.registration.sync"
    }

    static let shared = PersonRegistrationBackgroundTaskRegistrator()

    weak var service: PersonRegistrationBackgroundServiceProtocol? {
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

private extension PersonRegistrationBackgroundTaskRegistrator {
    func handlePendingTaskIfNeeded() {
        guard let service,
              let pendingTask else {
            return
        }
        service.fetchStateInBackground(asPartOf: pendingTask)
        self.pendingTask = nil
    }
}
