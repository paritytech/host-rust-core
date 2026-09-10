import UIKit
import BackgroundTasks

protocol PersonRegistrationBackgroundServiceProtocol: AnyObject {
    var delegate: PersonRegistrationBackgroundServiceDelegate? { get set }

    func startObserving()
    func stopObserving()
    func fetchStateInBackground(asPartOf task: BGTask)
}

protocol PersonRegistrationBackgroundServiceDelegate: AnyObject {
    var isBackgroundSyncDone: Bool { get }

    func didScheduleBackgroundFetch(justEnteredBackground: Bool)
    func didCancelScheduledBackgroundFetch()
    func didUpdateSyncStateInBackground(_ state: PersonRegistrationSyncState)
}

final class PersonRegistrationBackgroundService: PersonRegistrationBackgroundServiceProtocol {
    weak var delegate: PersonRegistrationBackgroundServiceDelegate?

    private let fetcher: PersonRegistrationStateFetcher
    private let logger: LoggerProtocol

    private var isInBackground = false

    init(
        fetcher: PersonRegistrationStateFetcher,
        logger: LoggerProtocol
    ) {
        self.fetcher = fetcher
        self.logger = logger
        cancelScheduledBackgroundFetch()
    }

    // MARK: - PersonRegistrationBackgroundServiceProtocol

    func startObserving() {
        PersonRegistrationBackgroundTaskRegistrator.shared.service = self
        addAppLifecycleObservers()
    }

    func stopObserving() {
        PersonRegistrationBackgroundTaskRegistrator.shared.service = nil
        removeAppLifecycleObservers()
        cancelScheduledBackgroundFetch()
    }

    func fetchStateInBackground(asPartOf task: BGTask) {
        logger.info("[BGTask] handler invoked for \(stateRefreshTaskId)")

        if isDone {
            logger.info("[BGTask] \(stateRefreshTaskId) already done, completing immediately")
            task.setTaskCompleted(success: true)
            return
        }

        var completed = false

        task.expirationHandler = { [weak self] in
            self?.logger.info("[BGTask] expiration handler fired for \(self?.stateRefreshTaskId ?? "")")
            self?.fetcher.cancelFetch()

            if !completed {
                completed = true
                task.setTaskCompleted(success: false)
            }
        }

        fetcher.fetchSyncState { [weak self] state in
            let success: Bool

            if let state {
                success = true
                self?.delegate?.didUpdateSyncStateInBackground(state)
            } else {
                success = false
            }

            if !completed {
                completed = true
                self?.logger.info("[BGTask] \(self?.stateRefreshTaskId ?? "") completed, success: \(success)")
                task.setTaskCompleted(success: success)
            }
        }

        scheduleBackgroundFetchIfNeeded(justEnteredBackground: false)
    }
}

// MARK: - Private

private extension PersonRegistrationBackgroundService {
    enum TimeIntervals {
        static let taskEarliestBeginInterval = TimeInterval(60 * 60 * 2)
    }

    var stateRefreshTaskId: String {
        PersonRegistrationBackgroundTaskRegistrator.BackgroundTaskIds.stateRefresh
    }

    var isDone: Bool {
        delegate?.isBackgroundSyncDone == true
    }

    func addAppLifecycleObservers() {
        removeAppLifecycleObservers()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func removeAppLifecycleObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    func appDidEnterBackground() {
        isInBackground = true
        scheduleBackgroundFetchIfNeeded(justEnteredBackground: true)
    }

    @objc
    func appDidBecomeActive() {
        guard isInBackground else {
            return
        }
        isInBackground = false
        cancelScheduledBackgroundFetch()
    }

    func scheduleBackgroundFetchIfNeeded(justEnteredBackground: Bool) {
        if isDone {
            return
        }

        let request = BGProcessingTaskRequest(identifier: stateRefreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeIntervals.taskEarliestBeginInterval)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info(
                "[BGTask] submitted request \(stateRefreshTaskId), earliestBeginDate: \(request.earliestBeginDate?.description ?? "nil")"
            )
        } catch {
            logger.error(
                "[BGTask] submit failed for \(stateRefreshTaskId): \(error.localizedDescription)"
            )
        }

        delegate?.didScheduleBackgroundFetch(justEnteredBackground: justEnteredBackground)
    }

    func cancelScheduledBackgroundFetch() {
        logger.info("[BGTask] cancelling pending request \(stateRefreshTaskId)")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: stateRefreshTaskId)
        delegate?.didCancelScheduledBackgroundFetch()
    }
}
