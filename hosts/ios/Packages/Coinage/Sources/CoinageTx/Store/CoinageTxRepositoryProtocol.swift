import AsyncExtensions
import Foundation

/// Persistence for durability entries and handoff marks — the single seam that folds the former
/// `DurabilityStoring` + `CoinageTransacting` store abstraction into one repository.
///
/// Entries are never deleted; terminal rows stay as history because `minter(of:)` and
/// `consumers(of:)` must still see them.
///
/// Handoff marks are a separate insert-only record whose presence survives any later state change.
public protocol CoinageTxRepositoryProtocol: Sendable {
    /// Mints a ``CoinageTxId`` per registration, inserts an entry for each, and hands the ids to
    /// `onCommit` — all inside one transaction, after `validation`, so nothing can move what it
    /// checked and a caller can take ownership before any other reader sees the rows. All commit or
    /// none do. `validation` runs once against the whole batch (it must reject within-batch conflicts
    /// itself, since the rows do not exist yet). A throw from `validation` leaves nothing behind.
    /// `onCommit` receives the minted ids in registration order; each entry gets a monotonic
    /// `sequence`.
    func register(
        _ registrations: [CoinageTxRegistration],
        validation: @escaping (any CoinageTxValidationContextProtocol) throws -> Void,
        onCommit: @escaping ([CoinageTxId]) -> Void
    ) async throws

    /// Atomically applies `verdict` iff the entry's current status still equals
    /// `expectedCurrentStatus` and is not terminal — the read and the write share one transaction,
    /// so the status cannot move between them. Returns whether it wrote. The single guarded writer
    /// of a rule verdict.
    @discardableResult
    func updateTxStatus(
        for id: CoinageTxId,
        expectedCurrentStatus: CoinageTxStatus,
        verdict: Verdict
    ) async throws -> Bool

    /// Every entry, live and terminal, ordered by `sequence`.
    func getAllEntries() async throws -> [CoinageTxEntry]

    /// The entry with this id, if any.
    func getEntry(id: CoinageTxId) async throws -> CoinageTxEntry?

    /// A stream of an entry's status: the current value, then every change. For a caller that must
    /// await a terminal outcome (offboarding an external payment) rather than fire-and-forget.
    func subscribeStatus(id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus>

    /// Every entry registered under `groupId`, ordered by `sequence`. The correlation key an
    /// operation supplies (e.g. a transfer's message id) so its transactions can be found together.
    func getOperationGroupStatuses(_ groupId: CoinageTxGroupId) async throws -> [CoinageTxEntry]

    /// A stream of the entries registered under `groupId`: the current set, then every change,
    /// ordered by `sequence`. For a claim that reports its group's progress until nothing in it is
    /// live.
    func subscribeOperationGroupStatuses(_ groupId: CoinageTxGroupId) -> AnyAsyncSequence<[CoinageTxEntry]>

    /// The entry that minted this asset, if any.
    func minter(of asset: OwnAsset) async throws -> CoinageTxEntry?

    /// Every entry consuming this input, including terminal ones.
    func consumers(of input: CoinageTxInput) async throws -> [CoinageTxEntry]

    /// Provisionally marks assets handed off (`.pending`) after running `validation` in the same
    /// transaction — so nothing can claim them between the check and the mark, and a throw rolls the
    /// whole thing back. Released on relaunch unless committed.
    func precommitHandOff(
        _ assets: [OwnAsset],
        validation: @escaping (any CoinageTxValidationContextProtocol) throws -> Void
    ) async throws

    /// Promotes provisional marks to final (`.committed`) — the keys have durably left. Keyed by
    /// ``OwnAsset/publicKey``, the form the transport can name without reconstructing the asset.
    func commitHandoffs(_ keys: [PublicKey]) async throws

    /// Clears every uncommitted (`.pending`) mark. Runs once, on launch.
    func releaseUncommittedHandoffs() async throws

    func handedOffCoins() async throws -> [OwnAsset]
}

public extension CoinageTxRepositoryProtocol {
    /// Handoff marks as a set of ``OwnAsset/publicKey``, the form the DAG and callers compare against.
    func getHandoffKeys() async throws -> Set<PublicKey> {
        try await Set(handedOffCoins().map(\.publicKey))
    }

    /// The entry's current status, if it exists.
    func getStatus(_ id: CoinageTxId) async throws -> CoinageTxStatus? {
        try await getEntry(id: id)?.status
    }
}
