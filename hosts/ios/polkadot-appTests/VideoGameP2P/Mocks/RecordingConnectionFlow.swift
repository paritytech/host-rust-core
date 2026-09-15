@testable import polkadot_app
import AsyncExtensions
import Foundation

final class RecordingConnectionFlow: VideoGamePeerConnectionFlowing {
    private let lock = NSLock()
    private let stream: AsyncStream<VideoGamePeerConnectionFlowEvent>
    private let continuation: AsyncStream<VideoGamePeerConnectionFlowEvent>.Continuation

    private var started = 0
    private var cancelled = 0

    var events: AnyAsyncSequence<VideoGamePeerConnectionFlowEvent> {
        stream.eraseToAnyAsyncSequence()
    }

    var startCount: Int {
        lock.withLock { started }
    }

    var cancelCount: Int {
        lock.withLock { cancelled }
    }

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func start() async {
        lock.withLock {
            started += 1
        }
    }

    func cancel() async {
        lock.withLock {
            cancelled += 1
        }
        continuation.finish()
    }

    func emit(_ event: VideoGamePeerConnectionFlowEvent) {
        continuation.yield(event)
    }
}
