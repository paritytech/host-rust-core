import Foundation
import WebRTC
import MessageExchangeKit
import SubstrateSdk
import Individuality

protocol VideoGamePeerComponentMaking {
    func makeSignalingSession(
        delegate: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>
    ) async throws -> VideoGameSignalingSession

    func makeConnectionFlow(
        session: VideoGameSignalingSession
    ) -> VideoGamePeerConnectionFlowing
}

final class VideoGamePeerComponentFactory {
    private let sessionFactory: VideoGameSessionMaking
    private let gameIndex: GamePallet.GameIndex
    private let peerAccountId: AccountId
    private let peerLogger: LoggerProtocol

    private let isInitiator: Bool
    private let localVideoTrack: RTCVideoTrack?
    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let configFactory: WebRTCConfigMaking

    init(
        sessionFactory: VideoGameSessionMaking,
        gameIndex: GamePallet.GameIndex,
        peerAccountId: AccountId,
        isInitiator: Bool,
        localVideoTrack: RTCVideoTrack?,
        peerConnectionFactory: RTCPeerConnectionFactory,
        configFactory: WebRTCConfigMaking,
        peerLogger: LoggerProtocol
    ) {
        self.sessionFactory = sessionFactory
        self.gameIndex = gameIndex
        self.peerAccountId = peerAccountId
        self.peerLogger = peerLogger
        self.isInitiator = isInitiator
        self.localVideoTrack = localVideoTrack
        self.peerConnectionFactory = peerConnectionFactory
        self.configFactory = configFactory
    }
}

extension VideoGamePeerComponentFactory: VideoGamePeerComponentMaking {
    func makeSignalingSession(
        delegate: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>
    ) async throws -> VideoGameSignalingSession {
        try await sessionFactory.makeSession(
            gameIndex: gameIndex,
            peerAccountId: peerAccountId,
            delegate: delegate,
            peerLogger: peerLogger
        )
    }

    func makeConnectionFlow(
        session: VideoGameSignalingSession
    ) -> VideoGamePeerConnectionFlowing {
        VideoGamePeerConnectionFlow(
            session: session,
            isInitiator: isInitiator,
            localVideoTrack: localVideoTrack,
            peerConnectionFactory: peerConnectionFactory,
            configFactory: configFactory,
            peerLogger: peerLogger
        )
    }
}
