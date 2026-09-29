import Foundation
import SubstrateSdk
import AsyncExtensions
import WebRTC
import Individuality

/// Reports connection state changes from the 1:N peer engine manager.
protocol VideoGameConnectionManagerDelegate: AnyObject {
    func connectionManager(
        _ manager: VideoGameConnectionManaging,
        didUpdateConnectionStates states: [AccountId: VideoGamePeerEngineState]
    )
}

protocol VideoGameConnectionManaging: AnyObject {
    var delegate: VideoGameConnectionManagerDelegate? { get set }

    /// The local video track to send over the peer connection.
    var localVideoTrack: RTCVideoTrack? { get set }

    /// Reconciles the set of active remote players with the current peer engines.
    /// Creates new engines for added players and disposes engines for removed players.
    func setConnectedPlayers(_ remotePlayers: Set<AccountId>, gameIndex: GamePallet.GameIndex)

    /// Disposes all peer engines and clears state, optionally clearing their
    /// persisted offer IDs after disposal.
    func disconnectAll(clearsPersistedOfferIds: Bool)

    func peerEngineState(for accountId: AccountId) -> VideoGamePeerEngineState?
}

final class VideoGameConnectionManager {
    weak var delegate: VideoGameConnectionManagerDelegate?
    var localVideoTrack: RTCVideoTrack?

    private let localAccountId: AccountId
    private let callbackQueue: DispatchQueue
    private let logger: LoggerProtocol

    private let mutex = NSLock()
    private var peerEngines: [AccountId: VideoGamePeerEngine] = [:]
    private var peerStates: [AccountId: VideoGamePeerEngineState] = [:]
    private var observationTasks: [AccountId: Task<Void, Never>] = [:]
    private let contextFactory: VideoGamePeerEngineContextMaking

    init(
        localAccountId: AccountId,
        contextFactory: VideoGamePeerEngineContextMaking,
        callbackQueue: DispatchQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.localAccountId = localAccountId
        self.callbackQueue = callbackQueue
        self.contextFactory = contextFactory
        self.logger = logger

        logger.debug("Initialized with local account: \(localAccountId.toHex())")
    }

    deinit {
        logger.debug("Deinit")
    }
}

// MARK: - VideoGameConnectionManaging

extension VideoGameConnectionManager: VideoGameConnectionManaging {
    func setConnectedPlayers(_ remotePlayers: Set<AccountId>, gameIndex: GamePallet.GameIndex) {
        let currentPeers = mutex.withLock { Set(peerEngines.keys) }
        let actualRemotePlayers = remotePlayers.filter { $0 != localAccountId }

        let toAdd = actualRemotePlayers.subtracting(currentPeers)
        let toRemove = currentPeers.subtracting(actualRemotePlayers)

        // Clear offer IDs and dispose removed engines (offer is no longer valid)
        for accountId in toRemove {
            removeEngine(for: accountId, clearsOfferId: true)
        }

        // Create new engines
        for accountId in toAdd {
            addEngine(for: accountId, gameIndex: gameIndex)
        }

        if !toAdd.isEmpty || !toRemove.isEmpty {
            let total = mutex.withLock { peerEngines.count }
            logger.debug(
                "Players updated: added=\(toAdd.count), removed=\(toRemove.count), total=\(total)"
            )
        }
    }

    func disconnectAll(clearsPersistedOfferIds: Bool) {
        let allAccountIds = mutex.withLock { Array(peerEngines.keys) }

        for accountId in allAccountIds {
            removeEngine(for: accountId, clearsOfferId: clearsPersistedOfferIds)
        }
    }

    func peerEngineState(for accountId: SubstrateSdk.AccountId) -> VideoGamePeerEngineState? {
        mutex.withLock {
            peerStates[accountId]
        }
    }
}

// MARK: - Private

private extension VideoGameConnectionManager {
    func addEngine(for remoteAccountId: AccountId, gameIndex: GamePallet.GameIndex) {
        let peerLogger = TaggedLogger(
            tag: makePeerTag(remoteAccountId: remoteAccountId),
            logger: logger
        )
        let engine = VideoGamePeerEngine(
            remoteAccountId: remoteAccountId,
            gameIndex: gameIndex,
            localVideoTrack: localVideoTrack,
            contextFactory: contextFactory,
            peerLogger: peerLogger
        )

        // Start observing engine state
        let task = Task { [weak self, weak engine] in
            guard let engine else { return }

            do {
                let stateStream = await engine.stateStream()

                for try await state in stateStream {
                    guard !Task.isCancelled else { return }
                    self?.handleStateUpdate(state, for: remoteAccountId)
                }
            } catch {
                self?.logger.error("State observation error for peer: \(error)")
            }
        }

        mutex.withLock {
            peerEngines[remoteAccountId] = engine
            peerStates[remoteAccountId] = .connecting
            observationTasks[remoteAccountId] = task
        }

        Task {
            await engine.start()
        }
    }

    func removeEngine(for remoteAccountId: AccountId, clearsOfferId: Bool) {
        let engine: VideoGamePeerEngine? = mutex.withLock {
            observationTasks[remoteAccountId]?.cancel()
            observationTasks.removeValue(forKey: remoteAccountId)

            let engine = peerEngines.removeValue(forKey: remoteAccountId)
            peerStates.removeValue(forKey: remoteAccountId)
            return engine
        }

        if let engine {
            Task {
                await engine.dispose()

                if clearsOfferId {
                    await engine.clearPersistedOfferId()
                }
            }
        }
    }

    func handleStateUpdate(_ state: VideoGamePeerEngineState, for remoteAccountId: AccountId) {
        let states: [AccountId: VideoGamePeerEngineState]? = mutex.withLock {
            guard peerEngines[remoteAccountId] != nil else {
                return nil
            }
            peerStates[remoteAccountId] = state
            return peerStates
        }

        guard let states else {
            return
        }

        callbackQueue.async { [weak self] in
            guard let self else { return }
            delegate?.connectionManager(self, didUpdateConnectionStates: states)
        }
    }

    func makePeerTag(remoteAccountId: AccountId) -> String {
        String(remoteAccountId.toHex().prefix(8))
    }
}
