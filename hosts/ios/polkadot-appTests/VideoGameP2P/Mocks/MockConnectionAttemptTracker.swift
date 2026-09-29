@testable import polkadot_app
import Foundation
import Individuality
import SubstrateSdk

final class MockConnectionAttemptTracker: ConnectionAttemptTracking {
    private let lock = NSLock()
    private var offerId: String?
    private let persistedOfferIdStream: AsyncStream<String>
    private let persistedOfferIdContinuation: AsyncStream<String>.Continuation

    init() {
        (persistedOfferIdStream, persistedOfferIdContinuation) = AsyncStream.makeStream()
    }

    var persistedOfferIds: AsyncStream<String> {
        persistedOfferIdStream
    }

    func getLastOfferId(gameIndex _: GamePallet.GameIndex, remoteAccountId _: AccountId) -> String? {
        lock.withLock { offerId }
    }

    func persistOfferId(
        _ offerId: String,
        gameIndex _: GamePallet.GameIndex,
        remoteAccountId _: AccountId
    ) {
        lock.withLock { self.offerId = offerId }
        persistedOfferIdContinuation.yield(offerId)
    }

    func clearOfferId(gameIndex _: GamePallet.GameIndex, remoteAccountId _: AccountId) {
        lock.withLock { offerId = nil }
    }
}
