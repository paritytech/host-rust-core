import Foundation
import Operation_iOS
import AsyncExtensions
import Foundation_iOS
import PolkadotUI
import SubstrateSdk
import Individuality

final class DIM1ChatInteractor {
    // MARK: - Dependencies

    private let flowState: DIM1SharedFlowStateProtocol
    private let notificationService: DIM1NotificationServicing
    private let logger: LoggerProtocol

    // MARK: - State Actor

    private let state: DIM1ChatInteractorState

    // MARK: - State Subjects

    private let widgetStateSubject = AsyncCurrentValueSubject<DIM1WidgetState?>(nil)
    private let messageEventSubject = AsyncPassthroughSubject<DIM1MessageEvent>()

    // MARK: - Observation Tasks

    private var stateObservationTask: Task<Void, Error>?
    private var personObservationTask: Task<Void, Error>?
    private var evidenceLocalStateObservationTask: Task<Void, Never>?
    private var gameInfoObservationTask: Task<Void, Error>?

    // MARK: - Background Sync

    private var backgroundSyncService: DIM1BackgroundServiceProtocol?

    var evidenceSubmissionLocalFactory: EvidenceLocalDataProviderFactoryProtocol {
        flowState.evidenceSubmissionFactory
    }

    init(
        flowState: DIM1SharedFlowStateProtocol,
        notificationService: DIM1NotificationServicing,
        modelFactory: ProofOfInkChatEvidenceModelFactoryProtocol = ProofOfInkChatEvidenceModelFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.flowState = flowState
        self.notificationService = notificationService
        self.logger = logger

        state = DIM1ChatInteractorState(evidenceModelFactory: modelFactory, logger: logger)
    }
}

// MARK: - DIM1ChatInteracting

extension DIM1ChatInteractor: DIM1ChatInteracting {
    func setup() async {
        await setupStateCallbacks()

        startObservingCommonStateStore()
        startObservingRegistration()
        startObservingEvidenceLocalState()
        startObservingGameInfo()
    }

    func observeWidgetState() -> AnyAsyncSequence<DIM1WidgetState?> {
        widgetStateSubject
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }

    func observeMessageEvents() -> AnyAsyncSequence<DIM1MessageEvent> {
        messageEventSubject.eraseToAnyAsyncSequence()
    }

    func retryEvidenceUpload() async {
        await state.retryUpload()
    }

    func switchToCurrentDim() async throws {
        guard await !(state.offboardInProgress) else {
            return
        }

        do {
            let terminationService = try flowState.createGameTerminationService()
            await state.updateOffboard(inProgress: true)
            _ = try await terminationService.offBoardWrapper().asyncExecute()
            await state.updateOffboard(inProgress: false)
        } catch {
            logger.error("Game termination failed: \(error) ")
            await state.updateOffboard(inProgress: false)
            throw error
        }
    }
}

// MARK: - State Callbacks Setup

private extension DIM1ChatInteractor {
    func setupStateCallbacks() async {
        await state.setOnWidgetUpdate { [weak self, logger] widgetState in
            logger.debug("State: \(String(describing: widgetState))")

            self?.widgetStateSubject.send(widgetState)
            self?.updateBackgroundSyncObservation(for: widgetState)
        }

        await state.setOnMessageEvent { [weak self, logger] event in
            logger.debug("Event: \(event)")

            self?.messageEventSubject.send(event)
        }

        await state.setEvidenceUploadingServiceProvider { [flowState] in
            flowState.createEvidenceSubmissionServices()
        }

        await state.setEvidenceFileTrackingTaskProvider { [flowState, logger, weak state] selectedState in
            Task {
                do {
                    let evidenceId = String(selectedState.since)
                    let fileManager = flowState.evidenceFileManagerFactory.createManager(evidenceId: evidenceId)
                    let mediator = flowState.createEvidenceStateMediator(for: fileManager)

                    logger.debug("Will start recoding monitoring")

                    for try await recordingState in mediator.stateStream() {
                        logger.debug("Will update recording monitoring state: \(recordingState)")
                        await state?.updateEvidenceRecordingState(recordingState)
                    }
                } catch {
                    logger.error("Recording monitoring failed")
                }
            }
        }

        var familyCache: [ProofOfInkPallet.FamilyIndex: ProofOfInkPallet.FamilyId] = [:]
        await state.setTattooFamilyProvider { [flowState] familyIndex in
            guard familyCache[familyIndex] == nil else {
                return familyCache[familyIndex]
            }

            let identifier = try await flowState.proofOfInkFactory
                .fetchFamily(
                    using: familyIndex,
                    chainRegistry: flowState.chainRegistry,
                    chainId: flowState.proofOfInkChainId
                )
                .asyncExecute()?
                .id

            familyCache[familyIndex] = identifier

            return identifier
        }
    }
}

// MARK: - State Observing

private extension DIM1ChatInteractor {
    func startObservingCommonStateStore() {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [flowState, state, logger] in
            do {
                for try await remoteState in flowState.commonStateStore.observe() {
                    logger.debug("Remote state: \(String(describing: remoteState))")
                    await state.updateRemoteState(remoteState)
                }
            } catch {
                logger.error("Common state observation failed: \(error)")
            }
        }
    }

    func startObservingRegistration() {
        personObservationTask?.cancel()
        personObservationTask = Task { [flowState, state, logger] in
            do {
                for try await personState in flowState.personStateStore.observe() {
                    logger.debug("Person state: \(String(describing: personState))")
                    await state.updatePersonState(personState)
                }
            } catch {
                logger.error("Person observation failed: \(error)")
            }
        }
    }

    func startObservingEvidenceLocalState() {
        evidenceLocalStateObservationTask?.cancel()
        evidenceLocalStateObservationTask = Task { [evidenceSubmissionLocalFactory, state, logger, weak self] in
            let localStateStream = evidenceSubmissionLocalFactory
                .createEvidenceSubmissionLocalState()
                .asyncLastChangeStream()

            var sessionTask: Task<Void, Never>?

            do {
                for try await localState in localStateStream {
                    await state.updateEvidenceLocalState(localState)

                    logger.debug("Local state: \(String(describing: localState))")

                    if let localState {
                        if sessionTask == nil {
                            sessionTask = self?.createEvidenceSessionMonitoring(
                                localState.sessionId
                            )
                        }
                    } else {
                        sessionTask?.cancel()
                        sessionTask = nil

                        await state.updateEvidenceSession(nil)
                    }
                }
            } catch {
                logger.error("Evidence local state tracking failed: \(error)")
            }
        }
    }

    func createEvidenceSessionMonitoring(_ sessionId: String) -> Task<Void, Never>? {
        Task { [state, logger, evidenceSubmissionLocalFactory] in
            do {
                let sessionStream = evidenceSubmissionLocalFactory
                    .createEvidenceSubmissionSession(for: sessionId)
                    .asyncLastChangeStream()

                for try await session in sessionStream {
                    await state.updateEvidenceSession(session)
                }
            } catch {
                logger.error("Session tracking failed: \(error)")
            }
        }
    }

    func startObservingGameInfo() {
        gameInfoObservationTask?.cancel()
        gameInfoObservationTask = Task { [flowState, state, logger] in
            do {
                for try await gameInfo in flowState.gameInfoSyncService.observe() {
                    logger.debug("Game info: \(String(describing: gameInfo))")
                    await state.updateGameInfo(gameInfo)
                }
            } catch {
                logger.error("Game info observation failed: \(error)")
            }
        }
    }

    func updateBackgroundSyncObservation(for widgetState: DIM1WidgetState?) {
        switch widgetState {
        case .evidenceProvided,
             .evidenceApproved:
            startBackgroundSyncIfNeeded()
        default:
            stopBackgroundSync()
        }
    }

    func startBackgroundSyncIfNeeded() {
        guard backgroundSyncService == nil else {
            return
        }

        backgroundSyncService = flowState.createDIM1BackgroundService()
        backgroundSyncService?.delegate = self
        backgroundSyncService?.startObserving()

        logger.debug("Background sync service started")
    }

    func stopBackgroundSync() {
        guard backgroundSyncService != nil else {
            return
        }

        backgroundSyncService?.stopObserving()
        backgroundSyncService = nil

        logger.debug("Background sync service stopped")
    }
}

extension DIM1ChatInteractor: DIM1BackgroundServiceDelegate {
    var isBackgroundSyncDone: Bool {
        flowState.commonStateStore.currentState?.hasRelevantAliases == true
    }

    func didUpdateSyncStateInBackground(_ state: DIM1BackgroundSyncState) {
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
