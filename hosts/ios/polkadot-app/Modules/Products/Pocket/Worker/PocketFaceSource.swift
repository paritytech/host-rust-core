import Foundation
import TrUAPIHost

/// Where a card's face comes from: what the host already holds, then everything
/// the product draws.
protocol PocketFaceSourcing: Sendable {
    func faces(for key: PocketCardKey) -> AsyncStream<RendererNode>

    func send(action: String, payload: Data, for key: PocketCardKey)
}

/// Shows the kept face at once, then every live face the product draws, keeping
/// the newest.
///
/// Drawn first, kept second: the face is what the screen is waiting for, and
/// keeping it is bookkeeping the user should not wait on. A failure ends the
/// stream quietly rather than throwing — the card keeps the face it has and
/// waits for its product to draw again.
struct RealPocketFaceSource: PocketFaceSourcing {
    /// Resolved per call rather than held: the collection is not readable until
    /// the network's dotNS suffix is, and the cards are drawn before that.
    private let store: @Sendable () async -> (any PocketCardStore)?
    private let streams: any PocketFaceStreaming
    private let logger: LoggerProtocol

    init(
        store: @escaping @Sendable () async -> (any PocketCardStore)?,
        streams: any PocketFaceStreaming,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.store = store
        self.streams = streams
        self.logger = logger
    }

    func faces(for key: PocketCardKey) -> AsyncStream<RendererNode> {
        AsyncStream { continuation in
            let task = Task {
                let store = await store()

                if let kept = await store?.face(for: key) {
                    continuation.yield(kept)
                }

                do {
                    for try await face in streams.renderFaces(for: key) {
                        continuation.yield(face)
                        await store?.cacheFace(face, for: key)
                    }
                } catch {
                    logger.error("[pocket] the face stream for \(key.cardId.value) ended: \(error)")
                }

                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(action: String, payload: Data, for key: PocketCardKey) {
        streams.send(action: action, payload: payload, for: key)
    }
}
