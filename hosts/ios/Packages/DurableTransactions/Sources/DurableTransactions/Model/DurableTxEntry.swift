import Foundation
import Operation_iOS

public typealias DurableTxId = UUID

/// Groups the transactions registered together by one operation (e.g. a transfer's message id).
/// Supplied by the caller; `nil` for an ungrouped single submission.
public typealias DurableTxGroupId = String

/// Which consumer a transaction belongs to. One ledger serves every domain, and a recovery pass
/// evaluates each domain against its own ``TxCompletionOracle``.
public struct TxDomainId: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// What the engine knows about one transaction.
///
/// Deliberately thin: the bytes' hash, the window they are valid in, and what the ledger has concluded
/// so far. Anything domain-shaped reaches the rules only through ``TxCompletionOracle``.
public struct DurableTxEntry: Sendable, Equatable {
    public let id: DurableTxId
    public let domainId: TxDomainId

    /// Registration order. Monotonic, assigned by the store; recovery evaluates in this order so a
    /// transaction depending on another is never decided before its predecessor.
    public let sequence: Int64

    /// The operation that registered this transaction, `nil` for an ungrouped single submission.
    /// A label only: no rule reads it. It lets an operation's transactions be found together.
    public let groupId: DurableTxGroupId?

    /// Hash of the built extrinsic, fixed at registration. The body search looks block bodies up for it.
    public let txHash: Data

    /// The block the extrinsic's era is anchored to. The search window starts here, so no block below it
    /// can contain this extrinsic.
    public let checkpoint: BlockRef

    /// Blocks after `checkpoint` during which the extrinsic can still be included.
    public let mortality: UInt32

    /// Block where execution was first observed. Only ever written where success is already proven, so
    /// Rule 0 need only re-check that the block is still canonical.
    public let successDetectedAt: BlockRef?

    public let status: DurableTxStatus

    public let createdAt: Date

    public init(
        id: DurableTxId = UUID(),
        domainId: TxDomainId,
        sequence: Int64 = 0,
        groupId: DurableTxGroupId? = nil,
        txHash: Data,
        checkpoint: BlockRef,
        mortality: UInt32,
        successDetectedAt: BlockRef? = nil,
        status: DurableTxStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.domainId = domainId
        self.sequence = sequence
        self.groupId = groupId
        self.txHash = txHash
        self.checkpoint = checkpoint
        self.mortality = mortality
        self.successDetectedAt = successDetectedAt
        self.status = status
        self.createdAt = createdAt
    }
}

extension DurableTxEntry: Operation_iOS.Identifiable {
    public var identifier: String {
        id.uuidString
    }
}

public extension DurableTxEntry {
    /// The last block this transaction can still execute in. Widened so a checkpoint near `UInt32.max`
    /// cannot overflow.
    var mortalityEnd: UInt64 {
        UInt64(checkpoint.number) + UInt64(mortality)
    }

    /// True when the extrinsic can no longer be included: `finalizedNumber` is past the last block of
    /// the mortality window.
    func isWindowClosed(atFinalized finalizedNumber: UInt32) -> Bool {
        UInt64(finalizedNumber) > mortalityEnd
    }

    /// A copy with `status` replaced — the entry is immutable, so a status write rebuilds it.
    func withStatus(_ status: DurableTxStatus) -> DurableTxEntry {
        DurableTxEntry(
            id: id,
            domainId: domainId,
            sequence: sequence,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: successDetectedAt,
            status: status,
            createdAt: createdAt
        )
    }

    /// A copy with `successDetectedAt` replaced (`nil` clears the record).
    func withSuccessDetectedAt(_ block: BlockRef?) -> DurableTxEntry {
        DurableTxEntry(
            id: id,
            domainId: domainId,
            sequence: sequence,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: block,
            status: status,
            createdAt: createdAt
        )
    }

    /// A copy with `sequence` replaced — for a store assigning the order on insert.
    func withSequence(_ sequence: Int64) -> DurableTxEntry {
        DurableTxEntry(
            id: id,
            domainId: domainId,
            sequence: sequence,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: successDetectedAt,
            status: status,
            createdAt: createdAt
        )
    }
}

/// A transaction ready to be recorded: the hash of the already-built extrinsic and the window it can
/// land in. Carries no id — the repository mints the ``DurableTxId`` inside the write transaction.
public struct DurableTxRegistration: Sendable, Equatable {
    public let domainId: TxDomainId
    public let groupId: DurableTxGroupId?
    public let txHash: Data
    public let checkpoint: BlockRef
    public let mortalityBlocks: UInt32

    public init(
        domainId: TxDomainId,
        groupId: DurableTxGroupId?,
        txHash: Data,
        checkpoint: BlockRef,
        mortalityBlocks: UInt32
    ) {
        self.domainId = domainId
        self.groupId = groupId
        self.txHash = txHash
        self.checkpoint = checkpoint
        self.mortalityBlocks = mortalityBlocks
    }
}

public extension DurableTxRegistration {
    /// Builds the entry the repository stores — `id` minted by the store, `sequence` the next in order,
    /// status `.pending`.
    func makeEntry(id: DurableTxId, sequence: Int64) -> DurableTxEntry {
        DurableTxEntry(
            id: id,
            domainId: domainId,
            sequence: sequence,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: mortalityBlocks,
            status: .pending
        )
    }
}
