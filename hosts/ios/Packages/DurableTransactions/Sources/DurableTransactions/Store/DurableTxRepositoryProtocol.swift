import AsyncExtensions
import Foundation

/// Marker for the store's open write transaction.
///
/// A domain writes its own rows through its own store from inside a hook receiving this, so those rows
/// and the engine's row commit together. Throwing from the hook rolls both back. A concrete store hands
/// its own scope type (wrapping whatever its transaction is) and its domain-side counterpart recognises
/// it; a foreign scope is a programming error and must throw ``DurableTxError/foreignRegistrationScope``.
public protocol DurableTxRegistrationScope: AnyObject {}

/// Runs inside the registration transaction with the minted ids, in registration order.
public typealias DurableTxRegistrationHook = (any DurableTxRegistrationScope, [DurableTxId]) throws -> Void

/// The engine's durable ledger: one row per transaction it has taken responsibility for.
///
/// It stores nothing domain-shaped. Entries are never deleted; terminal rows stay as history because a
/// domain's provenance reads must still see them.
public protocol DurableTxRepositoryProtocol: Sendable {
    /// Mints a ``DurableTxId`` per registration, inserts an entry for each, and runs `onRegister` with
    /// the ids — all inside one transaction, so a domain can write its own rows and a caller can take
    /// ownership before any other reader sees the rows. All commit or none do: a throw from `onRegister`
    /// leaves nothing behind. Each entry gets a monotonic `sequence`. Returns the ids in registration order.
    func register(
        _ registrations: [DurableTxRegistration],
        onRegister: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId]

    /// Atomically applies `verdict` iff the entry's current status still equals `expectedCurrentStatus`
    /// and is not terminal — the read and the write share one transaction, so the status cannot move
    /// between them. Returns whether it wrote. The single guarded writer of a rule verdict.
    @discardableResult
    func updateTxStatus(
        for id: DurableTxId,
        expectedCurrentStatus: DurableTxStatus,
        verdict: Verdict
    ) async throws -> Bool

    /// Every entry of every domain, live and terminal, ordered by `sequence`.
    func getAllEntries() async throws -> [DurableTxEntry]

    /// Every entry of one domain, live and terminal, ordered by `sequence`. The recovery pass reads this
    /// twice per domain per pass, so a store backed by a database answers it with a predicate.
    func getAllEntries(domain: TxDomainId) async throws -> [DurableTxEntry]

    /// The entry with this id, if any.
    func getEntry(id: DurableTxId) async throws -> DurableTxEntry?

    /// A stream of an entry's status: the current value, then every change.
    func subscribeStatus(id: DurableTxId) -> AnyAsyncSequence<DurableTxStatus>

    /// Every entry registered under `groupId` in `domain`, ordered by `sequence`.
    func getGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) async throws -> [DurableTxEntry]

    /// A stream of the entries registered under `groupId`: the current set, then every change, ordered
    /// by `sequence`.
    func subscribeGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) -> AnyAsyncSequence<[DurableTxEntry]>
}

public extension DurableTxRepositoryProtocol {
    /// The entry's current status, if it exists.
    func getStatus(_ id: DurableTxId) async throws -> DurableTxStatus? {
        try await getEntry(id: id)?.status
    }
}
