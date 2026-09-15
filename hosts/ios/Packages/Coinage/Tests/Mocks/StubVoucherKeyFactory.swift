import Foundation
import KeyDerivation
@testable import Coinage

/// Derives fixed placeholder voucher key material and hands back a ``StubBandersnatchKeyManager``.
final class StubVoucherKeyFactory: VoucherKeyDeriving {
    func derivePublicKey(index _: DerivationIndex) throws -> PublicKey { Data(repeating: 0, count: 32) }
    func derivePrivateKey(index _: DerivationIndex) throws -> PrivateKey { Data(repeating: 0, count: 64) }

    func createKeyManager(index _: DerivationIndex) throws -> any BandersnatchKeyManaging {
        StubBandersnatchKeyManager()
    }
}
