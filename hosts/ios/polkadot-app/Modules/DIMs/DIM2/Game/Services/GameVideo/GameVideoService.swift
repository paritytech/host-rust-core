import Foundation
import Foundation_iOS
import WebRTC
import SubstrateSdk
import CommonService
import Individuality
import AsyncExtensions

protocol GameVideoServiceDelegate: AnyObject {
    func gameVideoService(
        _ service: GameVideoServicing,
        didUpdateState state: GameStateMachine.State?,
        isPlayersChanged: Bool
    )

    func gameVideoService(
        _ service: GameVideoServicing,
        didUpdateRTCIceConnectedFlags flags: [AccountId: Bool]
    )

    func gameVideoService(
        _ service: GameVideoServicing,
        didReceiveGestureAcceptance message: Game.DataChannelMessage.GestureAcceptanceMessage
    )
}

protocol GameVideoServicing: ApplicationServiceProtocol {
    func throttle(isGameFinished: Bool)
    func sendGestureAcceptance(for peerId: AccountId, vote: GameVideoVotingState)
}

// @unchecked Sendable: all mutable state confined to serial workQueue
final class GameVideoService: @unchecked Sendable {
    weak var delegate: GameVideoServiceDelegate?

    private let accountId: AccountId
    private let workQueue: DispatchQueue
    private let connectionManager: VideoGameConnectionManaging
    private let rtcClient: RTCClient
    private let stateMachine: GameStateTransition
    private let gameSyncService: GameInfoSyncServicing
    private let gameDashboardTelemetry: GameDashboardTelemetryServicing?
    private let logger: LoggerProtocol

    private var activePlayers = Set<AccountId>()
    private var preconnectPlayers = Set<AccountId>()
    private var currentGameIndex: GamePallet.GameIndex?
    private var currentGameInfo: GameInfo?
    private var gestureAcceptanceObservationTask: Task<Void, Never>?
    private var gameInfoObservationTask: Task<Void, Never>?

    init(
        accountId: AccountId,
        workQueue: DispatchQueue,
        connectionManager: VideoGameConnectionManaging,
        rtcClient: RTCClient,
        stateMachine: GameStateTransition,
        gameSyncService: GameInfoSyncServicing,
        gameDashboardTelemetry: GameDashboardTelemetryServicing? = nil,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountId = accountId
        self.workQueue = workQueue
        self.connectionManager = connectionManager
        self.rtcClient = rtcClient
        self.stateMachine = stateMachine
        self.gameSyncService = gameSyncService
        self.gameDashboardTelemetry = gameDashboardTelemetry
        self.logger = logger
    }

    deinit {
        logger.debug("Deinit")
        gameInfoObservationTask?.cancel()
        gestureAcceptanceObservationTask?.cancel()
    }
}

extension GameVideoService: GameVideoServicing {
    func setup() {
        connectionManager.delegate = self
        connectionManager.localVideoTrack = rtcClient.localVideoTrack

        stateMachine.add(
            observer: self,
            queue: workQueue
        ) { [weak self] _, state in
            self?.logger.debug("State observer dispatched, state=\(String(describing: state))")
            self?.handleNewState(state)
        }

        startGameInfoObservation()
    }

    func throttle() {
        throttle(isGameFinished: false)
    }

    func throttle(isGameFinished: Bool) {
        logger.debug("Tearing down observers and connection")
        stateMachine.throttle()
        stateMachine.remove(observer: self)
        gameInfoObservationTask?.cancel()
        gameInfoObservationTask = nil
        disconnect(isGameFinished: isGameFinished)
    }

    func sendGestureAcceptance(for peerId: AccountId, vote: GameVideoVotingState) {
        dispatchPrecondition(condition: .onQueue(workQueue))

        guard
            let state = stateMachine.currentState,
            case let .round(round, _) = state
        else {
            logger.warning("Gesture acceptance should only be sent while a round is active")
            return
        }

        let acceptanceState: Game.DataChannelMessage.GestureAcceptanceMessage.State =
            switch vote {
            case .positive:
                .accept
            case .negative,
                 .notDecided:
                .unnaccept
            }

        let message = Game.DataChannelMessage.GestureAcceptanceMessage(
            roundIndex: round.roundIndex,
            acceptorAccountId: accountId,
            state: acceptanceState
        )

        do {
            let encodedMessage = try message.scaleEncoded()
            guard case let .connected(connection) = connectionManager.peerEngineState(for: peerId) else {
                logger.warning(
                    "Skipping gesture acceptance send for peer \(peerId.toHex().prefix(8)): data channel is unavailable"
                )
                return
            }

            // don't block work queue with synhronious writing
            Task { [logger] in
                do {
                    try await connection.multiplexedChannel.send(
                        data: encodedMessage,
                        useCaseId: Game.DataChannelMessage.GestureAcceptanceMessage.useCaseId
                    )
                } catch {
                    logger.warning(
                        "Skipping gesture acceptance send for peer \(peerId.toHex().prefix(8)): roundIndex \(round.roundIndex) is out of Int32 range"
                    )
                }
            }
        } catch {
            logger.warning(
                "Skipping gesture acceptance send for peer \(peerId.toHex().prefix(8)): roundIndex \(round.roundIndex) due to encoding failure"
            )
        }
    }
}

extension GameVideoService: VideoGameConnectionManagerDelegate {
    func connectionManager(
        _: VideoGameConnectionManaging,
        didUpdateConnectionStates states: [AccountId: VideoGamePeerEngineState]
    ) {
        var flags = [AccountId: Bool]()
        var connectedChannels = [MultiplexedDataChannel]()

        for (accountId, state) in states {
            switch state {
            case let .connected(connected):
                flags[accountId] = true
                connectedChannels.append(connected.multiplexedChannel)
                logger.debug("\(accountId.toHex().prefix(8)) connected, "
                    + "video track = \(connected.remoteVideoTrack != nil)")
                rtcClient.setRemoteVideoTrack(connected.remoteVideoTrack, for: accountId)
            case .connecting:
                flags[accountId] = false
                rtcClient.removeRemoteVideoTrack(for: accountId)
            case .disconnected:
                flags[accountId] = false
                rtcClient.removeRemoteVideoTrack(for: accountId)
            }
        }

        observeGestureAcceptanceChannels(connectedChannels)
        delegate?.gameVideoService(self, didUpdateRTCIceConnectedFlags: flags)

        sendReportingTelemetryIfNeeded(states: states)
    }
}

private extension GameVideoService {
    func startGameInfoObservation() {
        gameInfoObservationTask?.cancel()
        gameInfoObservationTask = Task { [weak self, gameSyncService] in
            do {
                for try await info in gameSyncService.observe() {
                    guard !Task.isCancelled else { return }
                    self?.workQueue.async {
                        self?.currentGameInfo = info
                    }
                }
            } catch {
                self?.logger.warning("Game info observation for telemetry stopped: \(error)")
            }
        }
    }

    func sendReportingTelemetryIfNeeded(states: [AccountId: VideoGamePeerEngineState]) {
        guard let telemetry = gameDashboardTelemetry else { return }
        guard let gameInfo = currentGameInfo else { return }

        let localAccount = accountId
        let roundsPeers: [[(peer: AccountId, state: VideoGamePeerEngineState)]] =
            gameInfo.sortedRounds.map { round in
                round.players
                    .filter { $0 != localAccount }
                    .map { player in
                        let state = states[player] ?? .disconnected
                        return (peer: player, state: state)
                    }
            }

        telemetry.sendReporting(
            localAccount: localAccount,
            roundsPeers: roundsPeers
        )
    }

    func handleNewState(_ state: GameStateMachine.State?) {
        let oldActivePlayers = activePlayers
        activePlayers = activePlayers(fromState: state)
        let isActivePlayersChanged = oldActivePlayers != activePlayers

        let oldPreconnectPlayers = preconnectPlayers
        preconnectPlayers = preconnectPlayers(fromState: state)
        let isPreconnectPlayersChanged = oldPreconnectPlayers != preconnectPlayers

        if isActivePlayersChanged || isPreconnectPlayersChanged {
            let allPlayers = activePlayers.union(preconnectPlayers)

            if let gameIndex = gameIndex(fromState: state) {
                currentGameIndex = gameIndex
                connectionManager.setConnectedPlayers(allPlayers, gameIndex: gameIndex)
                updateLocalCapture(fromState: state)
            } else {
                logger.debug("handleNewState: pre-disconnect")
                disconnect(isGameFinished: state?.isFinished == true)
                logger.debug("handleNewState: post-disconnect")
            }
        }

        logger.debug("handleNewState: pre-delegate state=\(String(describing: state))")
        delegate?.gameVideoService(
            self,
            didUpdateState: state,
            isPlayersChanged: isActivePlayersChanged
        )
        logger.debug("handleNewState: post-delegate")
    }

    func updateLocalCapture(fromState state: GameStateMachine.State?) {
        if shouldCaptureLocalVideo(fromState: state) {
            rtcClient.startLocalCapture()
        } else {
            rtcClient.stopLocalCapture()
        }
    }

    func shouldCaptureLocalVideo(fromState state: GameStateMachine.State?) -> Bool {
        switch state {
        case let .round(round, _):
            !round.players.isEmpty
        case let .preparing(info):
            info.preconnectPlayers?.isEmpty == false
        case .finished,
             nil:
            false
        }
    }

    func disconnect(isGameFinished: Bool) {
        logger.debug("disconnect: start")
        stopGestureAcceptanceObservationTask()
        logger.debug("disconnect: connectionManager.disconnectAll")
        // A finished game cannot reconnect. Clear its persisted offer IDs
        // after disposal so in-flight offers cannot restore them.
        connectionManager.disconnectAll(clearsPersistedOfferIds: isGameFinished)
        logger.debug("disconnect: rtcClient.removeAllRemoteVideoTracks")
        rtcClient.removeAllRemoteVideoTracks()
        logger.debug("disconnect: rtcClient.stopLocalCapture")
        rtcClient.stopLocalCapture()
        logger.debug("disconnect: done")
        currentGameIndex = nil
    }

    func stopGestureAcceptanceObservationTask() {
        gestureAcceptanceObservationTask?.cancel()
        gestureAcceptanceObservationTask = nil
    }

    func observeGestureAcceptanceChannels(_ channels: [MultiplexedDataChannel]) {
        stopGestureAcceptanceObservationTask()

        let gestureAcceptanceStreams = channels.map { channel in
            channel.subscribe(useCaseId: Game.DataChannelMessage.GestureAcceptanceMessage.useCaseId)
        }

        guard !gestureAcceptanceStreams.isEmpty else {
            return
        }

        gestureAcceptanceObservationTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for stream in gestureAcceptanceStreams {
                    group.addTask { [weak self] in
                        do {
                            for try await data in stream {
                                guard !Task.isCancelled else {
                                    return
                                }

                                self?.workQueue.async { [weak self] in
                                    self?.handleGestureAcceptanceMessageIfPossible(data)
                                }
                            }
                        } catch {}
                    }
                }

                await group.waitForAll()
            }
        }
    }

    func handleGestureAcceptanceMessageIfPossible(_ data: Data) {
        do {
            let message = try Game.DataChannelMessage.GestureAcceptanceMessage.fromScaleEncoded(data)
            handleGestureAcceptanceIfPossible(message)
        } catch {
            logger.error(
                "Failed to decode game data channel message: \(error)"
            )
        }
    }

    func handleGestureAcceptanceIfPossible(_ message: Game.DataChannelMessage.GestureAcceptanceMessage) {
        guard let currentRoundIndex = stateMachine.currentState?.gameplayRoundIndex else {
            logger.warning("Ignoring gesture acceptance: no active gameplay round")
            return
        }

        guard message.roundIndex == currentRoundIndex else {
            logger.warning(
                "Ignoring gesture acceptance: roundIndex \(message.roundIndex) does not match current round \(currentRoundIndex)"
            )
            return
        }

        delegate?.gameVideoService(
            self,
            didReceiveGestureAcceptance: message
        )
    }

    func activePlayers(fromState state: GameStateMachine.State?) -> Set<AccountId> {
        switch state {
        case let .round(round, _):
            Set(round.players)
        case .preparing,
             .finished,
             nil:
            []
        }
    }

    func preconnectPlayers(fromState state: GameStateMachine.State?) -> Set<AccountId> {
        switch state {
        case let .preparing(info):
            info.preconnectPlayers.map { Set($0) } ?? []
        case let .round(round, _):
            round.preconnectPlayers.map { Set($0) } ?? []
        case .finished,
             nil:
            []
        }
    }

    func gameIndex(fromState state: GameStateMachine.State?) -> GamePallet.GameIndex? {
        switch state {
        case let .round(_, roundsInfo):
            roundsInfo.gameIndex
        case let .preparing(info):
            info.preconnectGameIndex
        case .finished,
             nil:
            nil
        }
    }
}
