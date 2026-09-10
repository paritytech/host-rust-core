import UIKit
import BackgroundTasks
import StructuredConcurrency
import KeyDerivation
import Individuality

protocol PersonSelfIncludeBackgroundServiceProtocol: AnyObject {
    var delegate: PersonSelfIncludeBackgroundServiceDelegate? { get set }

    func startObserving()
    func stopObserving()
    func fetchStateInBackground(asPartOf task: BGTask)
}

protocol PersonSelfIncludeBackgroundServiceDelegate: AnyObject {
    /// Returns nil when no scheduling is needed (member not in onboarding queue,
    /// suspended, included, or feature unavailable). Returns the earliest fire
    /// date otherwise; the date may be in the past if the member is already eligible.
    var selfIncludeEarliestBeginDate: Date? { get }
}

final class PersonSelfIncludeBackgroundService: PersonSelfIncludeBackgroundServiceProtocol {
    weak var delegate: PersonSelfIncludeBackgroundServiceDelegate?

    private let fetcher: PersonSelfIncludeStateFetching
    private let submitter: SelfIncludeSubmitting
    private let logger: LoggerProtocol

    private var isInBackground = false
    private var workTask: Task<Void, Never>?

    init(
        fetcher: PersonSelfIncludeStateFetching,
        submitter: SelfIncludeSubmitting,
        logger: LoggerProtocol
    ) {
        self.fetcher = fetcher
        self.submitter = submitter
        self.logger = logger
        cancelScheduledBackgroundFetch()
    }

    // MARK: - PersonSelfIncludeBackgroundServiceProtocol

    func startObserving() {
        PersonSelfIncludeBackgroundTaskRegistrator.shared.service = self
        addAppLifecycleObservers()
    }

    func stopObserving() {
        PersonSelfIncludeBackgroundTaskRegistrator.shared.service = nil
        removeAppLifecycleObservers()
        cancelScheduledBackgroundFetch()
        workTask?.cancel()
    }

    func fetchStateInBackground(asPartOf task: BGTask) {
        logger.info("[BGTask] handler invoked for \(taskId)")

        workTask?.cancel()

        let work = Task { [weak self] in
            guard let self else { return }
            await runFetchAndSubmit(task: task)
        }
        workTask = work

        task.expirationHandler = { [weak self] in
            self?.logger.info("[BGTask] expiration handler fired for \(self?.taskId ?? "")")
            work.cancel()
        }
    }
}

// MARK: - Private

private extension PersonSelfIncludeBackgroundService {
    var taskId: String {
        PersonSelfIncludeBackgroundTaskRegistrator.BackgroundTaskIds.selfIncludeSubmit
    }

    func runFetchAndSubmit(task: BGTask) async {
        let result: PersonRegistration.SelfIncludeEligibility
        do {
            result = try await fetcher.fetchEligibility()
        } catch {
            logger.error("[BGTask] eligibility fetch failed: \(error)")
            task.setTaskCompleted(success: false)
            return
        }

        switch result {
        case let .eligible(callValidAt):
            await triggerSubmission(callValidAt: callValidAt, task: task)
        case .waiting:
            logger.info("[BGTask] not yet eligible; rescheduling")
            scheduleBackgroundFetchIfNeeded()
            task.setTaskCompleted(success: true)
        case .unavailable,
             .notOnboarding:
            logger.info("[BGTask] no submission needed for result \(result)")
            task.setTaskCompleted(success: true)
        }
    }

    func triggerSubmission(callValidAt: UInt64, task: BGTask) async {
        do {
            try await submitter.submitSelfInclude(callValidAt: callValidAt)
            logger.info("[BGTask] submitter reported successfully)")
            task.setTaskCompleted(success: true)
        } catch {
            logger.error("[BGTask] submitter failed: \(error)")
            task.setTaskCompleted(success: false)

            // retry in 5 minutes
            let retryDate = Date.now + .secondsInMinute * 5
            scheduleBackgroundFetch(earliestBeginDate: retryDate)
        }
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
        scheduleBackgroundFetchIfNeeded()
    }

    @objc
    func appDidBecomeActive() {
        guard isInBackground else { return }
        isInBackground = false
        cancelScheduledBackgroundFetch()
    }

    func scheduleBackgroundFetchIfNeeded() {
        guard let earliestBeginDate = delegate?.selfIncludeEarliestBeginDate else {
            cancelScheduledBackgroundFetch()
            return
        }

        scheduleBackgroundFetch(earliestBeginDate: earliestBeginDate)
    }

    func scheduleBackgroundFetch(earliestBeginDate: Date) {
        let request = BGProcessingTaskRequest(identifier: taskId)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info(
                "[BGTask] submitted request \(taskId), earliestBeginDate: \(earliestBeginDate)"
            )
        } catch {
            logger.error("[BGTask] submit failed for \(taskId): \(error.localizedDescription)")
        }
    }

    func cancelScheduledBackgroundFetch() {
        logger.info("[BGTask] cancelling pending request \(taskId)")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
    }
}
