@testable import polkadot_app
import AsyncExtensions
import Foundation

final class MockConnectionFlow: VideoGamePeerConnectionFlowing {
    private let stream: AsyncStream<VideoGamePeerConnectionFlowEvent>
    private let continuation: AsyncStream<VideoGamePeerConnectionFlowEvent>.Continuation

    var events: AnyAsyncSequence<VideoGamePeerConnectionFlowEvent> {
        stream.eraseToAnyAsyncSequence()
    }

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func start() async {}

    func cancel() async {
        continuation.finish()
    }
}
