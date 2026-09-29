import Foundation
import AsyncExtensions
import MessageExchangeKit
import SubstrateSdk
import Individuality

/// Synchronization point for a single peer engine lifecycle.
///
/// The engine adapts external callbacks. The context owns mutable lifecycle
/// state: current session, current connection flow, ordered incoming envelopes,
/// reconnection decisions, offer tracking and state publication.
actor VideoGamePeerEngineContext {
    private let stateSubject = AsyncCurrentValueSubject<VideoGamePeerEngineState>(.connecting)

    private let componentFactory: VideoGamePeerComponentMaking
    private let peerSessionDelegate: any VideoGamePeerSessionDelegating
    private let attemptTracker: ConnectionAttemptTracking
    private let gameIndex: GamePallet.GameIndex
    private let remoteAccountId: AccountId
    private let peerLogger: LoggerProtocol

    private var lifecycleTask: Task<Void, Never>?
    private var currentFlowTask: Task<Void, Never>?
    private var session: VideoGameSignalingSession?
    private var currentFlow: VideoGamePeerConnectionFlowing?

    private var isDisposed = false
    private var lastEmittedState: VideoGamePeerEngineState?

    init(
        componentFactory: VideoGamePeerComponentMaking,
        peerSessionDelegate: any VideoGamePeerSessionDelegating,
        attemptTracker: ConnectionAttemptTracking,
        gameIndex: GamePallet.GameIndex,
        remoteAccountId: AccountId,
        peerLogger: LoggerProtocol
    ) {
        self.componentFactory = componentFactory
        self.peerSessionDelegate = peerSessionDelegate
        self.attemptTracker = attemptTracker
        self.gameIndex = gameIndex
        self.remoteAccountId = remoteAccountId
        self.peerLogger = peerLogger
    }

    deinit {
        peerLogger.debug("Deinit")
        lifecycleTask?.cancel()
        currentFlowTask?.cancel()
    }

    func stateStream() -> AnyAsyncSequence<VideoGamePeerEngineState> {
        stateSubject.eraseToAnyAsyncSequence()
    }

    func start() -> Bool {
        guard lifecycleTask == nil, !isDisposed else {
            return false
        }

        lifecycleTask = Task { [weak self] in
            await self?.runLifecycle()
        }

        return true
    }

    func dispose() async {
        isDisposed = true
        peerSessionDelegate.finishIncomingEnvelopes()

        let lifecycleTask = lifecycleTask
        let currentFlowTask = currentFlowTask
        let currentFlow = currentFlow

        self.lifecycleTask = nil
        self.currentFlowTask = nil
        self.currentFlow = nil
        session = nil

        lifecycleTask?.cancel()
        currentFlowTask?.cancel()

        await currentFlow?.cancel()
        await currentFlowTask?.value
        await lifecycleTask?.value
    }

    func clearPersistedOfferId() {
        peerLogger.debug("Clearing persisted offer id")
        attemptTracker.clearOfferId(gameIndex: gameIndex, remoteAccountId: remoteAccountId)
    }
}

private extension VideoGamePeerEngineContext {
    func emitState(_ state: VideoGamePeerEngineState) {
        guard !isDisposed else {
            return
        }

        if let lastEmittedState, lastEmittedState.isEquivalent(to: state) {
            return
        }

        lastEmittedState = state
        stateSubject.send(state)
    }

    func runLifecycle() async {
        do {
            let delegate = AnyPeerSessionDelegate(peerSessionDelegate)
            let session = try await componentFactory.makeSignalingSession(delegate: delegate)
            try Task.checkCancellation()

            guard !isDisposed else {
                return
            }

            self.session = session

            await sendReconnectedIfNeeded(session)
            await startConnectionFlow(session: session)
            await observeIncomingEnvelopes(session: session)
            await cancelCurrentFlow()
        } catch is CancellationError {
            return
        } catch {
            peerLogger.error("Connection failed: \(error)")
            emitState(.disconnected)
        }
    }

    func observeIncomingEnvelopes(session: VideoGameSignalingSession) async {
        for await batch in peerSessionDelegate.incomingEnvelopes {
            guard !Task.isCancelled, !isDisposed else {
                break
            }

            guard let reconnection = await session.reconnection(
                in: batch,
                isValidOffer: isReconnectionRequestValid
            ) else {
                await session.handleIncomingEnvelopes(batch)
                continue
            }

            peerLogger.debug("Reconnection requested for offer ID: \(reconnection.offerId)")

            await cancelCurrentFlow()

            guard !Task.isCancelled, !isDisposed else {
                break
            }

            await session.resetForReconnection()
            await startConnectionFlow(session: session)

            await session.handleIncomingEnvelopes(reconnection.following)
        }
    }

    func startConnectionFlow(session: VideoGameSignalingSession) async {
        guard !isDisposed else {
            return
        }

        let flow = componentFactory.makeConnectionFlow(session: session)
        currentFlow = flow
        emitState(.connecting)

        currentFlowTask = Task { [weak self, flow] in
            do {
                let events = await flow.events

                for try await event in events {
                    try Task.checkCancellation()
                    await self?.handleConnectionFlowEvent(event)
                }
            } catch is CancellationError {
                return
            } catch {
                await self?.handleConnectionFlowError(error)
            }
        }

        await flow.start()
    }

    func cancelCurrentFlow() async {
        let task = currentFlowTask
        let flow = currentFlow

        currentFlowTask = nil
        currentFlow = nil

        task?.cancel()
        await flow?.cancel()
        await task?.value
    }

    func handleConnectionFlowEvent(_ event: VideoGamePeerConnectionFlowEvent) {
        guard !isDisposed else {
            return
        }

        switch event {
        case let .state(state):
            emitState(state)

        case let .activeOfferId(offerId):
            attemptTracker.persistOfferId(
                offerId,
                gameIndex: gameIndex,
                remoteAccountId: remoteAccountId
            )
        }
    }

    func handleConnectionFlowError(_ error: Error) {
        guard !isDisposed else {
            return
        }

        peerLogger.error("Connection flow failed: \(error)")
        emitState(.disconnected)
    }

    func sendReconnectedIfNeeded(_ session: VideoGameSignalingSession) async {
        guard
            let lastOfferId = attemptTracker.getLastOfferId(
                gameIndex: gameIndex,
                remoteAccountId: remoteAccountId
            )
        else {
            return
        }

        await session.sendReconnected(lastOfferId)
        peerLogger.debug("Sent reconnected with offer ID: \(lastOfferId)")
    }

    func isReconnectionRequestValid(offerId: String) -> Bool {
        let lastOfferId = attemptTracker.getLastOfferId(
            gameIndex: gameIndex,
            remoteAccountId: remoteAccountId
        )

        guard lastOfferId == offerId else {
            peerLogger.debug("Ignoring reconnected with mismatched offer ID: \(offerId)")
            return false
        }

        return true
    }
}
