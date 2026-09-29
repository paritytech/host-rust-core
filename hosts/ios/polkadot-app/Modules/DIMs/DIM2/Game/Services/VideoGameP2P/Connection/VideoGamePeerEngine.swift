import Foundation
import WebRTC
import AsyncExtensions
import SubstrateSdk
import Individuality

/// Manages a single WebRTC connection to one remote player.
final class VideoGamePeerEngine {
    private let peerLogger: LoggerProtocol

    private let context: VideoGamePeerEngineContext

    init(
        remoteAccountId: AccountId,
        gameIndex: GamePallet.GameIndex,
        localVideoTrack: RTCVideoTrack?,
        contextFactory: VideoGamePeerEngineContextMaking,
        peerLogger: LoggerProtocol
    ) {
        self.peerLogger = peerLogger

        context = contextFactory.makeContext(
            remoteAccountId: remoteAccountId,
            gameIndex: gameIndex,
            localVideoTrack: localVideoTrack,
            peerLogger: peerLogger
        )

        peerLogger.debug("Initialized")
    }

    deinit {
        peerLogger.debug("Deinit")
    }

    func stateStream() async -> AnyAsyncSequence<VideoGamePeerEngineState> {
        await context.stateStream()
    }

    /// Begins the connection lifecycle. The context actor guarantees the
    /// task is started once and rejects starts after disposal.
    func start() async {
        let didStart = await context.start()

        if !didStart {
            peerLogger.debug("Start ignored: lifecycle already started or disposed")
        }
    }

    func dispose() async {
        await context.dispose()
    }

    func clearPersistedOfferId() async {
        await context.clearPersistedOfferId()
    }
}
