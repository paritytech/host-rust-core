@testable import polkadot_app
import Foundation
import MessageExchangeKit

final class RecordingPeerComponentFactory: VideoGamePeerComponentMaking {
    private let createdFlowStream: AsyncStream<RecordingConnectionFlow>
    private let createdFlowContinuation: AsyncStream<RecordingConnectionFlow>.Continuation

    init() {
        (createdFlowStream, createdFlowContinuation) = AsyncStream.makeStream()
    }

    var createdFlows: AsyncStream<RecordingConnectionFlow> {
        createdFlowStream
    }

    func makeSignalingSession(
        delegate _: AnyPeerSessionDelegate<OpaqueVideoGameSignalingEnvelope>
    ) async throws -> VideoGameSignalingSession {
        VideoGameP2PTestFactory.makeSession()
    }

    func makeConnectionFlow(
        session _: VideoGameSignalingSession
    ) -> VideoGamePeerConnectionFlowing {
        let flow = RecordingConnectionFlow()
        createdFlowContinuation.yield(flow)
        return flow
    }
}
