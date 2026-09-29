import Foundation
import AsyncExtensions
import CommonService

final class PersonhoodBackgroundService {
    private let personhoodRegistrationService: PersonhoodRegistrationServicing
    private let syncStateStore: DetermineStateSyncStore
    private let backgroundService: PersonRegistrationBackgroundServiceProtocol
    private let selfIncludeBackgroundService: PersonSelfIncludeBackgroundServiceProtocol
    private let notificationService: PersonRegistrationNotificationServicing
    private let logger: LoggerProtocol

    private var isBackgroundServiceObserving = false
    private var isSelfIncludeServiceObserving = false
    private var syncStateObservationTask: Task<Void, Never>?

    init(
        personhoodRegistrationService: PersonhoodRegistrationServicing,
        syncStateStore: DetermineStateSyncStore,
        backgroundService: PersonRegistrationBackgroundServiceProtocol,
        selfIncludeBackgroundService: PersonSelfIncludeBackgroundServiceProtocol,
        notificationService: PersonRegistrationNotificationServicing,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.personhoodRegistrationService = personhoodRegistrationService
        self.syncStateStore = syncStateStore
        self.backgroundService = backgroundService
        self.selfIncludeBackgroundService = selfIncludeBackgroundService
        self.notificationService = notificationService
        self.logger = logger
    }
}

extension PersonhoodBackgroundService: ApplicationServiceProtocol {
    func setup() {
        personhoodRegistrationService.stateObserver = self
        startObservingSyncState()
    }

    func throttle() {
        syncStateObservationTask?.cancel()
        syncStateObservationTask = nil
        stopBackgroundServiceIfNeeded()
        stopSelfIncludeServiceIfNeeded()
    }
}

private extension PersonhoodBackgroundService {
    func startObservingSyncState() {
        syncStateObservationTask?.cancel()
        syncStateObservationTask = Task { [weak self, syncStateStore, logger] in
            do {
                for try await syncState in syncStateStore.observe() {
                    self?.updateBackgroundServiceObservation(for: syncState)
                }
            } catch {
                logger.error("Sync state observation failed: \(error)")
            }
        }
    }

    func updateBackgroundServiceObservation(for syncState: DetermineStateSyncState?) {
        guard syncState?.personId != nil else {
            stopBackgroundServiceIfNeeded()
            return
        }

        if isBackgroundSyncDone {
            stopBackgroundServiceIfNeeded()
        } else {
            startBackgroundServiceIfNeeded()
        }
    }

    func startBackgroundServiceIfNeeded() {
        guard !isBackgroundServiceObserving else {
            return
        }
        isBackgroundServiceObserving = true
        backgroundService.delegate = self
        backgroundService.startObserving()

        logger.debug("Person registration background service started")
    }

    func stopBackgroundServiceIfNeeded() {
        guard isBackgroundServiceObserving else {
            return
        }
        isBackgroundServiceObserving = false
        backgroundService.stopObserving()

        logger.debug("Person registration background service stopped")
    }

    func updateSelfIncludeServiceObservation(for remoteState: PersonRegistration.RemoteState) {
        switch remoteState.selfIncludeEligibility {
        case .unavailable,
             .notOnboarding:
            stopSelfIncludeServiceIfNeeded()
        case .waiting,
             .eligible:
            startSelfIncludeServiceIfNeeded()
        }
    }

    func startSelfIncludeServiceIfNeeded() {
        guard !isSelfIncludeServiceObserving else {
            return
        }
        isSelfIncludeServiceObserving = true
        selfIncludeBackgroundService.delegate = personhoodRegistrationService
        selfIncludeBackgroundService.startObserving()

        logger.debug("Self-include background service started")
    }

    func stopSelfIncludeServiceIfNeeded() {
        guard isSelfIncludeServiceObserving else {
            return
        }
        isSelfIncludeServiceObserving = false
        selfIncludeBackgroundService.stopObserving()

        logger.debug("Self-include background service stopped")
    }
}

extension PersonhoodBackgroundService: PersonRegistrationBackgroundServiceDelegate {
    var isBackgroundSyncDone: Bool {
        syncStateStore.currentState?.hasRelevantAliases == true
    }

    func didUpdateSyncStateInBackground(_ state: PersonRegistrationSyncState) {
        notificationService.handleBackgroundSyncStateUpdate(state)
    }

    func didScheduleBackgroundFetch(justEnteredBackground: Bool) {
        notificationService.handleBackgroundFetchScheduled(
            justEnteredBackground: justEnteredBackground,
            isBackgroundSyncDone: isBackgroundSyncDone
        )
    }

    func didCancelScheduledBackgroundFetch() {
        notificationService.cancelPendingNotifications()
    }
}

extension PersonhoodBackgroundService: PersonhoodRegistrationStateObserving {
    func registrationService(
        _: PersonhoodRegistrationServicing,
        didUpdate _: PersonRegistration.LocalState
    ) {}

    func registrationService(
        _: PersonhoodRegistrationServicing,
        didUpdate remoteState: PersonRegistration.RemoteState
    ) {
        updateSelfIncludeServiceObservation(for: remoteState)
    }
}
