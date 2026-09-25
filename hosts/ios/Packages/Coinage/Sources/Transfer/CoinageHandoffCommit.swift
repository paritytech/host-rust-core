import Foundation

/// An idempotent handle for committing a recipient handoff.
///
/// Held from the moment the assets are chosen until whatever carries their keys is durable, then
/// committed. Where that is depends on the transport — for a chat payment it is the message row —
/// so the commit belongs inside the transaction that writes it: a crash in between would otherwise
/// clear the reservation while a peer already holds the keys.
///
/// Ordinary uncommitted reservations are released on relaunch. Native custody instead commits its
/// marks alongside a durable derivation journal before returning this handle.
public protocol CoinageHandoffCommit: Sendable {
    func commit() async throws
}

/// A ``CoinageHandoffCommit`` backed by the asset ledger: `commit()` promotes the provisional marks on
/// `assets` to final.
struct StoreHandoffCommit: CoinageHandoffCommit {
    let assets: [OwnAsset]
    let ledger: any CoinageAssetLedgerProtocol

    func commit() async throws {
        try await ledger.commitHandoffs(assets.map(\.publicKey))
    }
}
