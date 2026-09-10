@testable import polkadot_app
import Foundation
import MessageExchangeKit

final class NeverPeerComponentFactory: VideoGamePeerComponentMaking {
    private let stream: AsyncStream<Void>
    // Retained to keep the stream open until its consumer task is cancelled.
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func makeSignalingSession(
        delegate _: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>
    ) async throws -> VideoGameSignalingSession {
        for await _ in stream {}
        throw CancellationError()
    }

    func makeConnectionFlow(
        session _: VideoGameSignalingSession
    ) -> VideoGamePeerConnectionFlowing {
        MockConnectionFlow()
    }
}
