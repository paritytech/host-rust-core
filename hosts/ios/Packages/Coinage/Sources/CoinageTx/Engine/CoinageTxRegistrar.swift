import Foundation
import SDKLogger
import SubstrateSdk

/// The only thing that adds entries, and the only place the four invariants are enforced.
///
/// Accepts ``CoinageTxRegistration``s the service built up-front (each carries the extrinsic's hash,
/// the checkpoint, and the mortality window) and hands them to the repository, which validates and
/// inserts them in one transaction — so a rejected registration leaves nothing behind. Ownership is
/// taken inside that same transaction (`onCommit`), so a pass can never reach a committed entry
/// before the watcher does.
public struct CoinageTxRegistrar {
    private let store: any CoinageTxRepositoryProtocol
    private let validator: CoinageTxRegistrationValidator
    private let watched: CoinageTrackingTxSet
    private let logger: SDKLoggerProtocol?

    public init(
        store: any CoinageTxRepositoryProtocol,
        validator: CoinageTxRegistrationValidator,
        watched: CoinageTrackingTxSet,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.store = store
        self.validator = validator
        self.watched = watched
        self.logger = logger
    }

    /// Registers every registration atomically — all commit or none do — and takes ownership of
    /// each. Returns the minted ids in registration order.
    public func register(_ registrations: [CoinageTxRegistration]) async throws -> [CoinageTxId] {
        guard !registrations.isEmpty else { return [] }
        guard registrations.allSatisfy({ !$0.inputs.isEmpty || !$0.outputs.isEmpty }) else {
            throw CoinageTxError.emptyEntry
        }

        let owned = OwnedIds()
        do {
            try await store.register(
                registrations,
                validation: { [validator] context in try validator.validate(registrations, transaction: context) },
                onCommit: { [watched] ids in owned.take(ids, into: watched) }
            )
        } catch {
            // If ownership was taken but the transaction then rolled back, hand it back.
            owned.releaseAll(from: watched)
            throw error
        }

        logger?.debug("Registered \(registrations.count) entries")
        return owned.ids
    }

    /// Reserves `assets` against being spent again, rejecting any a live entry still claims — the
    /// mirror of the blocked-handoff invariant, run in the same transaction as the mark.
    public func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        let keys = Set(assets.map(\.publicKey))
        try await store.precommitHandOff(assets) { context in
            let claimed = try context.filterClaimed(keys)
            if let key = claimed.first {
                throw CoinageTxError.handoffOfClaimedAsset(key.toHex())
            }
        }
        return StoreHandoffCommit(assets: assets, store: store)
    }
}

/// Collects the ids `onCommit` mints so ownership can be handed back if the transaction rolls back.
/// A reference box: `onCommit` runs on the store's queue, and the enclosing `await` orders that
/// write before the read here.
private final class OwnedIds: @unchecked Sendable {
    private(set) var ids: [CoinageTxId] = []

    func take(_ ids: [CoinageTxId], into watched: CoinageTrackingTxSet) {
        self.ids = ids
        ids.forEach { watched.take($0) }
    }

    func releaseAll(from watched: CoinageTrackingTxSet) {
        ids.forEach { watched.release($0) }
    }
}
