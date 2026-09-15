import Coinage
import Foundation
import os

/// The real coin key factory over a fixed test entropy, so ``testKey`` yields curve-valid sr25519
/// public keys — the recycle crypto path builds an `SNPublicKey` from them.
private let testKeyFactory = CoinKeypairFactory(
    entropyManager: MockEntropyManager(entropy: Data(repeating: 0x01, count: 32))
)

/// Caches derived keys: mnemonic derivation is costly and ``testKey`` is called throughout the
/// suites; the lock keeps it safe under parallel test execution.
private let testKeyCache = OSAllocatedUnfairLock<[DerivationIndex: PublicKey]>(initialState: [:])

/// A deterministic, valid public key from a derivation index — distinct per index and stable across
/// calls, so the DAG, evidence, dedup, and handoff marks key consistently in tests.
func testKey(_ index: DerivationIndex) -> PublicKey {
    testKeyCache.withLock { cache in
        if let cached = cache[index] { return cached }
        guard let key = try? testKeyFactory.derivePublicKey(index: index) else {
            fatalError("Failed to derive test public key for index \(index)")
        }
        cache[index] = key
        return key
    }
}

extension BlockRef {
    /// Block `number` with a hash derived from it, so distinct numbers stay distinguishable.
    static func fixture(_ number: UInt32) -> BlockRef {
        BlockRef(number: number, hash: Data([UInt8(truncatingIfNeeded: number)]))
    }
}

extension CoinageTxRegistration {
    /// A registration checkpointed at block 100 with a 60-block window and a fixed `txHash` — the
    /// baseline the registrar suites vary from.
    static func fixture(
        inputs: [CoinageTxInput] = [],
        outputs: [OwnAsset] = [],
        checkpoint: BlockRef = .fixture(100),
        groupId: CoinageTxGroupId? = nil
    ) -> CoinageTxRegistration {
        CoinageTxRegistration(
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: checkpoint,
            mortalityBlocks: 60,
            groupId: groupId,
            inputs: inputs,
            outputs: outputs
        )
    }
}

extension CoinageTxEntry {
    /// A pending entry checkpointed at block 100 with a 60-block window — the baseline the
    /// durability suites vary from.
    static func fixture(
        id: CoinageTxId = UUID(),
        inputs: [CoinageTxInput] = [],
        outputs: [OwnAsset] = [],
        checkpoint: BlockRef = .fixture(100),
        status: CoinageTxStatus = .pending
    ) -> CoinageTxEntry {
        CoinageTxEntry(
            id: id,
            inputs: inputs,
            outputs: outputs,
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: checkpoint,
            mortality: 60,
            status: status
        )
    }
}
