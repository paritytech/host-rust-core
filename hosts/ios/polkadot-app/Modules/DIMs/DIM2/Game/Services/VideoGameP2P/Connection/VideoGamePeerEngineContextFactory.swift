import Foundation
import WebRTC
import SubstrateSdk
import Individuality

protocol VideoGamePeerEngineContextMaking {
    func makeContext(
        remoteAccountId: AccountId,
        gameIndex: GamePallet.GameIndex,
        localVideoTrack: RTCVideoTrack?,
        peerLogger: LoggerProtocol
    ) -> VideoGamePeerEngineContext
}

final class VideoGamePeerEngineContextFactory {
    private let localAccountId: AccountId
    private let sessionFactory: VideoGameSessionMaking
    private let attemptTracker: ConnectionAttemptTracking
    private let turnService: TURNCredentialsProviding

    init(
        localAccountId: AccountId,
        sessionFactory: VideoGameSessionMaking,
        attemptTracker: ConnectionAttemptTracking,
        turnService: TURNCredentialsProviding
    ) {
        self.localAccountId = localAccountId
        self.sessionFactory = sessionFactory
        self.attemptTracker = attemptTracker
        self.turnService = turnService
    }
}

extension VideoGamePeerEngineContextFactory: VideoGamePeerEngineContextMaking {
    func makeContext(
        remoteAccountId: AccountId,
        gameIndex: GamePallet.GameIndex,
        localVideoTrack: RTCVideoTrack?,
        peerLogger: LoggerProtocol
    ) -> VideoGamePeerEngineContext {
        let peerConnectionFactory = WebRTCPeerConnectionFactoryProvider.make()
        let componentFactory = VideoGamePeerComponentFactory(
            sessionFactory: sessionFactory,
            gameIndex: gameIndex,
            peerAccountId: remoteAccountId,
            isInitiator: localAccountId.precedes(remoteAccountId),
            localVideoTrack: localVideoTrack,
            peerConnectionFactory: peerConnectionFactory,
            // Pool size 0: 5 concurrent peers x 8 pre-gathered candidates was a real
            // STUN/TURN burst with no payoff. The game pre-connect is scheduled,
            // not user-blocking, so we gather on demand at offer time.
            configFactory: WebRTCConfigFactory(turnService: turnService, iceCandidatePoolSize: 0),
            peerLogger: peerLogger
        )

        return VideoGamePeerEngineContext(
            componentFactory: componentFactory,
            peerSessionDelegate: VideoGamePeerSessionDelegate(peerLogger: peerLogger),
            attemptTracker: attemptTracker,
            gameIndex: gameIndex,
            remoteAccountId: remoteAccountId,
            peerLogger: peerLogger
        )
    }
}
