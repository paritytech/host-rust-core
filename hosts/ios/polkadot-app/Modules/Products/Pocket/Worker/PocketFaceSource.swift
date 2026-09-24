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
    /// How often the newest face is written down. Faces change at frame rate,
    /// and each write serialises the whole tree into storage — at every frame
    /// that is the screen waiting on bookkeeping. What the card needs is one
    /// recent face to draw offline and at cold start, not every face it drew.
    private static let keepInterval = Duration.seconds(2)

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

                var unkept: RendererNode?
                var keptAt: ContinuousClock.Instant?

                do {
                    for try await face in streams.renderFaces(for: key) {
                        continuation.yield(face)
                        unkept = face

                        if let keptAt, keptAt.duration(to: .now) < Self.keepInterval { continue }
                        keptAt = .now
                        unkept = nil
                        await store?.cacheFace(face, for: key)
                    }
                } catch {
                    logger.error("[pocket] the face stream for \(key.cardId.value) ended: \(error)")
                }

                // The last face drawn is kept whatever the interval says, so a
                // card that stopped between writes is not read back later as
                // the face before the one it settled on.
                if let unkept {
                    await store?.cacheFace(unkept, for: key)
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
