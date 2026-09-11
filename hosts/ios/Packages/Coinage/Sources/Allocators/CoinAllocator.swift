import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation
import Operation_iOS

protocol CoinAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Coin
}

/// Actor isolation serialises the index counter's read-modify-write, so a single shared instance is
/// the only safe configuration — do not create more than one against the same index store.
actor CoinAllocator: CoinAllocating {
    private let storage: CoinageIndexstoreProtocol
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let keyFactory: any CoinKeyDeriving

    init(
        storage: CoinageIndexstoreProtocol,
        coinRepository: AnyDataProviderRepository<Coin>,
        keyFactory: any CoinKeyDeriving
    ) {
        self.storage = storage
        self.coinRepository = coinRepository
        self.keyFactory = keyFactory
    }

    /// Allocates a new coin index and persists the coin — with its on-chain public key cached so the
    /// durability layer never re-derives it — from the moment it is minted.
    func allocate(exponent: Int16) async throws -> Coin {
        let index = try storage.getNextIndex()
        let coin = try Coin(
            exponent: exponent,
            derivationIndex: index,
            age: nil,
            publicKey: keyFactory.derivePublicKey(index: index)
        )
        try await coinRepository.saveOperation({ [coin] }, { [] }).asyncExecute()
        return coin
    }
}
