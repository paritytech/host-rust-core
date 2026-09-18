import Foundation
import os
@testable import Coinage

/// Serves a configurable tracked-coin set; `save` is a no-op.
final class StubCoinService: CoinServiceProtocol, @unchecked Sendable {
    private let coins = OSAllocatedUnfairLock(initialState: [TrackedCoin]())

    init(coins: [TrackedCoin] = []) {
        set(coins: coins)
    }

    func set(coins: [TrackedCoin]) {
        self.coins.withLock { $0 = coins }
    }

    func fetchAllTrackedCoins() async throws -> [TrackedCoin] {
        coins.withLock { $0 }
    }

    func fetchCoins(publicKeys: Set<PublicKey>) async throws -> Set<Coin> {
        Set(coins.withLock { $0 }.map(\.coin).filter { publicKeys.contains($0.publicKey) })
    }

    func save(coins _: [Coin]) async throws {}
}
