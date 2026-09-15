import Foundation
import Operation_iOS

public typealias CoinageTxId = UUID

/// Groups the transactions registered together by one operation (e.g. a transfer's message id).
/// Supplied by the caller; `nil` for an ungrouped single submission.
public typealias CoinageTxGroupId = String

/// One tracked transaction: what it consumes, what it mints, and how far along it is.
///
/// The entry set is the source of truth for local asset state. Coin and voucher rows are
/// a projection of it, rebuilt by `ProjectionReconciler` at the head of every recovery
/// pass.
///
/// Deliberately operation-agnostic: every rule quantifies over `inputs` and `outputs`,
/// so all tracked calls share one resolution path and no per-operation dispatch exists.
public struct CoinageTxEntry: Sendable, Equatable {
    public let id: CoinageTxId

    /// Registration order. Monotonic, assigned by the store; recovery evaluates in this
    /// order so an entry consuming another's output is never decided before its
    /// predecessor.
    public let sequence: Int64

    public let inputs: [CoinageTxInput]
    public let outputs: [OwnAsset]

    /// The operation that registered this entry, `nil` for an ungrouped single submission.
    /// A label only: no rule reads it. It lets an operation's transactions be found together.
    public let groupId: CoinageTxGroupId?

    /// Hash of the built extrinsic, fixed at registration. Rule 7 searches block bodies for it.
    /// Immutable — an entry can never exist without the hash of the extrinsic it describes.
    public let txHash: Data

    /// Finalized head read once immediately before registration. Rule 7's search window
    /// starts here, so no block below it can contain this extrinsic.
    public let checkpoint: BlockRef

    /// Blocks after `checkpoint` during which the extrinsic can still be included.
    public let mortality: UInt32

    /// Block where execution was first observed. Only ever written where success is
    /// already proven, so Rule 0 need only re-check that the block is still canonical.
    public let successDetectedAt: BlockRef?

    public let status: CoinageTxStatus

    public let createdAt: Date

    public init(
        id: CoinageTxId = UUID(),
        sequence: Int64 = 0,
        inputs: [CoinageTxInput],
        outputs: [OwnAsset],
        groupId: CoinageTxGroupId? = nil,
        txHash: Data,
        checkpoint: BlockRef,
        mortality: UInt32,
        successDetectedAt: BlockRef? = nil,
        status: CoinageTxStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sequence = sequence
        self.inputs = inputs
        self.outputs = outputs
        self.groupId = groupId
        self.txHash = txHash
        self.checkpoint = checkpoint
        self.mortality = mortality
        self.successDetectedAt = successDetectedAt
        self.status = status
        self.createdAt = createdAt
    }
}

extension CoinageTxEntry: Operation_iOS.Identifiable {
    public var identifier: String {
        id.uuidString
    }
}

public extension CoinageTxEntry {
    /// A copy with `status` replaced — the entry is immutable, so a status write rebuilds it.
    func withStatus(_ status: CoinageTxStatus) -> CoinageTxEntry {
        CoinageTxEntry(
            id: id,
            sequence: sequence,
            inputs: inputs,
            outputs: outputs,
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
    func withSuccessDetectedAt(_ block: BlockRef?) -> CoinageTxEntry {
        CoinageTxEntry(
            id: id,
            sequence: sequence,
            inputs: inputs,
            outputs: outputs,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: block,
            status: status,
            createdAt: createdAt
        )
    }

    /// True when the extrinsic can no longer be included: `finalizedNumber` is past the last
    /// block of the entry's mortality window.
    ///
    /// Widened to `UInt64` so a checkpoint near `UInt32.max` cannot overflow into a false
    /// "window closed" and fail a live extrinsic.
    func isWindowClosed(atFinalized finalizedNumber: UInt32) -> Bool {
        UInt64(finalizedNumber) > UInt64(checkpoint.number) + UInt64(mortality)
    }
}

extension [CoinageTxEntry] {
    func receivedPublicKeys() -> Set<PublicKey> {
        var keys: Set<PublicKey> = []
        for entry in self {
            for input in entry.inputs {
                if case let .coin(.received(publicKey)) = input {
                    keys.insert(publicKey)
                }
            }
        }
        return keys
    }

    func finalizedSuccess() -> [CoinageTxEntry] {
        filter { $0.status == .finalizedSuccess }
    }

    func outputPublicKeys() -> Set<PublicKey> {
        Set(flatMap { $0.outputs.map(\.publicKey) })
    }
}
