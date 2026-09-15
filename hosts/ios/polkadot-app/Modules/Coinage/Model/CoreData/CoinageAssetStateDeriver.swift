import CoreData
import Coinage
import Foundation

/// Derives the durability overlay (``CoinageAssetState``) for a coin or voucher row from its
/// input/output entry relations.
enum CoinageAssetStateDeriver {
    static func state(handedOff: Bool, inputs: NSSet?, output: CDCoinageTxOutput?) -> CoinageAssetState {
        CoinageAssetState(
            handedOff: handedOff,
            consumerStatus: consumerStatus(of: inputs),
            minterStatus: status(of: output?.entry)
        )
    }

    /// At most one non-failure entry consumes an asset (Unique consumer invariant), so its status
    /// is the asset's live consumer status; a released (failed-only) asset has none.
    private static func consumerStatus(of inputs: NSSet?) -> CoinageTxStatus? {
        ((inputs as? Set<CDCoinageTxInput>) ?? [])
            .compactMap { status(of: $0.entry) }
            .first { $0 != .failure }
    }

    private static func status(of entry: CDCoinageTxEntry?) -> CoinageTxStatus? {
        entry.flatMap { CoinageTxStatus(rawValue: Int($0.status)) }
    }
}
