import Foundation

/// A transaction ready to be recorded: the hash of the already-built extrinsic, the window it can
/// land in, and what it consumes and mints. Carries no id — the repository mints the
/// ``CoinageTxId`` inside the write transaction and hands it to `onCommit`.
public struct CoinageTxRegistration: Sendable, Equatable {
    public let txHash: Data
    public let checkpoint: BlockRef
    public let mortalityBlocks: UInt32
    public let groupId: CoinageTxGroupId?
    public let inputs: [CoinageTxInput]
    public let outputs: [OwnAsset]

    public init(
        txHash: Data,
        checkpoint: BlockRef,
        mortalityBlocks: UInt32,
        groupId: CoinageTxGroupId?,
        inputs: [CoinageTxInput],
        outputs: [OwnAsset]
    ) {
        self.txHash = txHash
        self.checkpoint = checkpoint
        self.mortalityBlocks = mortalityBlocks
        self.groupId = groupId
        self.inputs = inputs
        self.outputs = outputs
    }
}

public extension CoinageTxRegistration {
    /// Builds the durable entry the repository stores — `id` minted by the store, `sequence` the
    /// next in order, status `.pending`.
    func makeEntry(id: CoinageTxId, sequence: Int64) -> CoinageTxEntry {
        CoinageTxEntry(
            id: id,
            sequence: sequence,
            inputs: inputs,
            outputs: outputs,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: mortalityBlocks,
            status: .pending
        )
    }
}
