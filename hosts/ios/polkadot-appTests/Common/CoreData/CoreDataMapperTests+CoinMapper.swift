import BigInt
import Coinage
import Foundation
import Operation_iOS
import Testing

@testable import polkadot_app

extension CoreDataMapperTests {
    @Suite("CoinMapper")
    struct CoinMapperTests {
        private let facade = UserDataStorageTestFacade()
        private var repo: AnyDataProviderRepository<Coin> { facade.makeRepo(mapper: CoinMapper()) }

        private func roundTrip(_ coin: Coin) async throws -> Coin {
            try await repo.saveOperation({ [coin] }, { [] }).asyncExecute()
            return try #require(
                try await repo.fetchOperation(by: { coin.identifier }, options: .init()).asyncExecute()
            )
        }

        @Test("roundTrip preserves the stored identity fields")
        func roundTrip() async throws {
            let original = Coin(
                exponent: 12,
                derivationIndex: 42,
                age: 5,
                isOnchain: true,
                publicKey: Data(repeating: 0x2A, count: 32)
            )
            let result = try await roundTrip(original)

            #expect(result.exponent == original.exponent)
            #expect(result.derivationIndex == original.derivationIndex)
            #expect(result.age == original.age)
            #expect(result.isOnchain == original.isOnchain)
            #expect(result.publicKey == original.publicKey)
        }

        @Test("nil age stored as -1 and restored to nil")
        func nilAgeRestoredToNil() async throws {
            let result = try await roundTrip(
                Coin(exponent: 8, derivationIndex: 100, age: nil, publicKey: Data(repeating: 0x64, count: 32))
            )
            #expect(result.age == nil)
        }

        // Status is derived on read from the durability graph, presence and age — not stored. With
        // no durability entries, only presence/age drive it.

        // Coin status is no longer a stored `Coin.state`; it is derived on read as a `TrackedCoin`
        // from the durability graph, presence and age, and is covered by the derive-on-read tests.
    }
}
