import Foundation
@testable import Coinage

/// Deterministic, disjoint key material derived from a derivation index.
///
/// The durability engine treats every public key as an opaque `Hashable` identity — it never does
/// crypto on one — so raw index-derived bytes are enough, and being a pure function of the index means
/// a shrunk trace replays to the same keys. Coin keys, voucher member keys and voucher alias keys are
/// kept disjoint so the same index names three different things without collision.
enum HarnessKeys {
    private static let size = 32

    /// A coin's on-chain key: the index in the first bytes, last byte 0.
    static func coinKey(_ index: DerivationIndex) -> PublicKey {
        indexBytes(index, marker: 0)
    }

    /// A voucher's on-chain member key: disjoint from `coinKey` by its last byte.
    static func voucherMemberKey(_ index: DerivationIndex) -> PublicKey {
        indexBytes(index, marker: 1)
    }

    /// A voucher's recycler alias public key: disjoint again, so the alias storage key is distinct
    /// from the member key it belongs to.
    static func voucherAliasKey(_ index: DerivationIndex) -> Data {
        indexBytes(index, marker: 2)
    }

    private static func indexBytes(_ index: DerivationIndex, marker: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: size)
        var value = index
        for offset in 0 ..< 8 {
            bytes[offset] = UInt8(truncatingIfNeeded: value)
            value >>= 8
        }
        bytes[size - 1] = marker
        return Data(bytes)
    }
}

extension CoinageChainState {
    /// The alias storage key the fake chain view reads for a voucher, given the exponent and ring it
    /// currently sits in — derived exactly as the fake writes it, so a read and a write agree.
    static func aliasKey(index: DerivationIndex, exponent: Int, ringIndex: Int) -> FakeAliasKey {
        FakeAliasKey(exponent: exponent, ringIndex: ringIndex, aliasPublicKey: HarnessKeys.voucherAliasKey(index))
    }
}
