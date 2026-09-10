import Foundation
@testable import Coinage

/// Derives fixed placeholder coin key material — enough for callers that only need well-formed bytes.
final class StubCoinKeyFactory: CoinKeyDeriving {
    func derivePublicKey(index _: DerivationIndex) throws -> PublicKey { Data(repeating: 0, count: 32) }
    func derivePrivateKey(index _: DerivationIndex) throws -> PrivateKey { Data(repeating: 0, count: 64) }
}
