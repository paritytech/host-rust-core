import BackgroundTasks

final class PersonSelfIncludeBackgroundTaskRegistrator {
    enum BackgroundTaskIds {
        static let selfIncludeSubmit = "io.novatech.person.self_include.submit"
    }

    static let shared = PersonSelfIncludeBackgroundTaskRegistrator()

    weak var service: PersonSelfIncludeBackgroundServiceProtocol? {
        didSet { handlePendingTaskIfNeeded() }
    }

    private var pendingTask: BGTask?

    private init() {}

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIds.selfIncludeSubmit,
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

private extension PersonSelfIncludeBackgroundTaskRegistrator {
    func handlePendingTaskIfNeeded() {
        guard let service,
              let pendingTask else {
            return
        }
        service.fetchStateInBackground(asPartOf: pendingTask)
        self.pendingTask = nil
    }
}
