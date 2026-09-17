import DurableTransactions
import Foundation

public extension TxDomainId {
    /// A domain for tests that need one and do not care which.
    static let test = TxDomainId("test")
}

public extension BlockRef {
    /// Block `number` with a hash derived from it, so distinct numbers stay distinguishable.
    static func fixture(_ number: UInt32) -> BlockRef {
        BlockRef(number: number, hash: Data([UInt8(truncatingIfNeeded: number)]))
    }
}

public extension DurableTxRegistration {
    /// A registration checkpointed at block 100 with a 60-block window and a fixed `txHash` — the
    /// baseline the registrar suites vary from.
    static func fixture(
        domainId: TxDomainId = .test,
        checkpoint: BlockRef = .fixture(100),
        groupId: DurableTxGroupId? = nil,
        txHash: Data = Data(repeating: 0xAB, count: 32)
    ) -> DurableTxRegistration {
        DurableTxRegistration(
            domainId: domainId,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortalityBlocks: 60
        )
    }
}

public extension DurableTxEntry {
    /// A pending entry checkpointed at block 100 with a 60-block window — the baseline the durability
    /// suites vary from.
    static func fixture(
        id: DurableTxId = UUID(),
        domainId: TxDomainId = .test,
        checkpoint: BlockRef = .fixture(100),
        mortality: UInt32 = 60,
        successDetectedAt: BlockRef? = nil,
        status: DurableTxStatus = .pending,
        groupId: DurableTxGroupId? = nil,
        txHash: Data? = nil
    ) -> DurableTxEntry {
        DurableTxEntry(
            id: id,
            domainId: domainId,
            groupId: groupId,
            txHash: txHash ?? Data("tx\(id.uuidString)".utf8),
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: successDetectedAt,
            status: status
        )
    }
}
