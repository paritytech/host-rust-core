import Foundation
import WebRTC
import AsyncExtensions

enum VideoGamePeerConnectionFlowEvent {
    case state(VideoGamePeerEngineState)
    case activeOfferId(String)
}

protocol VideoGamePeerConnectionFlowing: AnyObject {
    var events: AnyAsyncSequence<VideoGamePeerConnectionFlowEvent> { get async }

    func start() async
    func cancel() async
}

actor VideoGamePeerConnectionFlow {
    private let session: VideoGameSignalingSession
    private let isInitiator: Bool
    private let localVideoTrack: RTCVideoTrack?
    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let configFactory: WebRTCConfigMaking
    private let peerLogger: LoggerProtocol

    private nonisolated let eventsStream: AsyncStream<VideoGamePeerConnectionFlowEvent>
    private nonisolated let eventsContinuation: AsyncStream<VideoGamePeerConnectionFlowEvent>.Continuation

    private var flowTask: Task<Void, Never>?
    private var dataConnectionCreator: DataConnectionCreating?
    private var callCreator: CallCreatorProtocol?
    private var connectionWrapper: AsyncPeerConnectionWrapper?
    private var isCancelled = false

    init(
        session: VideoGameSignalingSession,
        isInitiator: Bool,
        localVideoTrack: RTCVideoTrack?,
        peerConnectionFactory: RTCPeerConnectionFactory,
        configFactory: WebRTCConfigMaking,
        peerLogger: LoggerProtocol
    ) {
        self.session = session
        self.isInitiator = isInitiator
        self.localVideoTrack = localVideoTrack
        self.peerConnectionFactory = peerConnectionFactory
        self.configFactory = configFactory
        self.peerLogger = peerLogger

        (eventsStream, eventsContinuation) = AsyncStream.makeStream()
    }

    deinit {
        peerLogger.debug("Deinit")
        flowTask?.cancel()
        eventsContinuation.finish()
    }
}

extension VideoGamePeerConnectionFlow: VideoGamePeerConnectionFlowing {
    var events: AnyAsyncSequence<VideoGamePeerConnectionFlowEvent> {
        eventsStream.eraseToAnyAsyncSequence()
    }

    func start() {
        guard flowTask == nil, !isCancelled else {
            return
        }

        flowTask = Task { [weak self] in
            await self?.run()
        }
    }

    func cancel() async {
        isCancelled = true
        flowTask?.cancel()
        await disposeResources()
        eventsContinuation.finish()
        await flowTask?.value
        flowTask = nil
    }
}

private extension VideoGamePeerConnectionFlow {
    func run() async {
        await performConnection()
        await disposeResources()
        eventsContinuation.finish()
    }

    func performConnection() async {
        guard !Task.isCancelled, !isCancelled else { return }

        emit(.state(.connecting))

        let role: CallRole = isInitiator ? .initiator : .acceptor
        peerLogger.debug("isInitiator = \(isInitiator)")

        let dataCreator = makeDataConnectionCreator(signaling: session, role: role)
        dataConnectionCreator = dataCreator

        guard let stateSequence = await createConnection(with: dataCreator) else {
            peerLogger.error("Data channel creation failed")
            emit(.state(.disconnected))
            return
        }

        peerLogger.debug("Establishing data channel...")

        guard let dataConnected = await waitDataChannelConnected(from: stateSequence) else {
            emit(.state(.disconnected))
            return
        }

        guard !Task.isCancelled, !isCancelled else { return }

        connectionWrapper = dataConnected.connection
        peerLogger.debug("Data channel established")

        if let offerId = await session.activeOfferId {
            emit(.activeOfferId(offerId))
        }

        await dataCreator.throttle()
        dataConnectionCreator = nil

        let localTracks = createVideoOnlyTracks()
        let mediaCreator = makeCallCreator(
            for: dataConnected,
            tracks: localTracks,
            role: role
        )
        callCreator = mediaCreator

        guard !Task.isCancelled, !isCancelled else { return }

        mediaCreator.setup()

        await reportMediaState(
            callCreator: mediaCreator,
            multiplexedChannel: mediaCreator.multiplexedChannel
        )
    }

    func makeDataConnectionCreator(
        signaling: PeerConnectionSignaling,
        role: CallRole
    ) -> DataConnectionCreating {
        switch role {
        case .initiator:
            DataConnectionInitiator(
                signaling: signaling,
                peerConnectionFactory: peerConnectionFactory,
                configFactory: configFactory,
                purpose: "video_game",
                candidateFilter: TcpHostCandidateFilter(),
                logger: peerLogger
            )
        case .acceptor:
            DataConnectionAcceptor(
                signaling: signaling,
                peerConnectionFactory: peerConnectionFactory,
                configFactory: configFactory,
                candidateFilter: TcpHostCandidateFilter(),
                logger: peerLogger
            )
        }
    }

    func createConnection(
        with dataCreator: DataConnectionCreating
    ) async -> AnyAsyncSequence<PeerDataConnectionState>? {
        do {
            return try await dataCreator.connect()
        } catch {
            guard !Task.isCancelled else { return nil }
            peerLogger.error("Failed to create connection: \(error)")
            return nil
        }
    }

    func waitDataChannelConnected(
        from sequence: AnyAsyncSequence<PeerDataConnectionState>
    ) async -> PeerDataConnectionState.Connected? {
        do {
            for try await state in sequence {
                guard !Task.isCancelled else { return nil }

                switch state {
                case .waiting,
                     .connecting:
                    continue
                case let .connected(model):
                    return model
                case .disconnected:
                    return nil
                }
            }
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            peerLogger.error("Data channel wait failed: \(error)")
            return nil
        }
    }

    func createVideoOnlyTracks() -> CallTracks {
        if let localVideoTrack {
            return CallTracks(videoTrack: localVideoTrack)
        }

        let videoSource = peerConnectionFactory.videoSource()
        let videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
        return CallTracks(videoTrack: videoTrack)
    }

    func makeCallCreator(
        for dataConnected: PeerDataConnectionState.Connected,
        tracks: CallTracks,
        role: CallRole
    ) -> CallCreatorProtocol {
        let transceiverConfigStrategy = TransceiverConfigStrategy(
            peerConnectionFactory: peerConnectionFactory,
            videoProfile: .game,
            logger: peerLogger
        )

        switch role {
        case .initiator:
            return CallInitiator(
                connectionWrapper: dataConnected.connection,
                dataChannelWrapper: dataConnected.dataChannel,
                localTracks: tracks,
                transceiverConfigStrategy: transceiverConfigStrategy,
                candidateFilter: TcpHostCandidateFilter(),
                logger: peerLogger
            )
        case .acceptor:
            return CallAcceptor(
                connectionWrapper: dataConnected.connection,
                dataChannelWrapper: dataConnected.dataChannel,
                localTracks: tracks,
                transceiverConfigStrategy: transceiverConfigStrategy,
                candidateFilter: TcpHostCandidateFilter(),
                logger: peerLogger
            )
        }
    }

    func reportMediaState(
        callCreator: CallCreatorProtocol,
        multiplexedChannel: MultiplexedDataChannel
    ) async {
        do {
            let stateSequence = callCreator.subscribeState()

            for try await state in stateSequence {
                guard !Task.isCancelled else { return }

                emit(.state(mapCallState(state, multiplexedChannel: multiplexedChannel)))

                if case .closed = state {
                    return
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            peerLogger.error("Media state reporting error: \(error)")
            emit(.state(.disconnected))
        }
    }

    func mapCallState(
        _ state: CallCreationState,
        multiplexedChannel: MultiplexedDataChannel
    ) -> VideoGamePeerEngineState {
        switch state {
        case .creating:
            .connecting
        case let .ready(tracks):
            .connected(.init(
                multiplexedChannel: multiplexedChannel,
                remoteVideoTrack: tracks.videoTrack
            ))
        case .closed:
            .disconnected
        }
    }

    func disposeResources() async {
        let callCreator = callCreator
        let dataConnectionCreator = dataConnectionCreator
        let connectionWrapper = connectionWrapper

        self.callCreator = nil
        self.dataConnectionCreator = nil
        self.connectionWrapper = nil

        callCreator?.throttle()
        await dataConnectionCreator?.cancel()
        await connectionWrapper?.close()
    }

    func emit(_ event: VideoGamePeerConnectionFlowEvent) {
        eventsContinuation.yield(event)
    }
}
