import Foundation

/// A handoff that is reserved but not yet final.
///
/// Held from the moment the assets are chosen until whatever carries their keys is durable, then
/// committed. Where that is depends on the transport — for a chat payment it is the message row —
/// so the commit belongs inside the transaction that writes it: a crash in between would otherwise
/// clear the reservation while a peer already holds the keys.
///
/// Leaving a handle uncommitted is safe: a relaunch releases every provisional mark, returning the
/// coins. The only way for a mark to outlive the process is for the keys to have actually left.
public protocol CoinageHandoffCommit: Sendable {
    func commit() async throws
}

/// A ``CoinageHandoffCommit`` backed by the durability store: `commit()` promotes the provisional
/// marks on `assets` to final.
struct StoreHandoffCommit: CoinageHandoffCommit {
    let assets: [OwnAsset]
    let store: any CoinageTxRepositoryProtocol

    func commit() async throws {
        try await store.commitHandoffs(assets.map(\.publicKey))
    }
}
