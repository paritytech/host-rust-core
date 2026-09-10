import BigInt
import Foundation

/// The result of external payment planning, doubling as a preview
/// that exposes privacy information before execution.
public enum ExternalPaymentPreview {
    /// Enough ready vouchers to cover the amount.
    case ready(Selection)

    /// Not enough ready vouchers but coins are available for recycling.
    case loadCoins(Selection)

    /// Vouchers or coins exist but aren't mature yet — retry after the given date.
    case needsReschedule(after: Date, Selection)

    /// Permanent failure — total available value is insufficient.
    case notEnoughBalance
}

// MARK: - Selection

public extension ExternalPaymentPreview {
    /// Pre-computed selection of vouchers/coins with amount breakdowns.
    struct Selection {
        /// Vouchers selected for this payment (offboarding candidates for `.ready`,
        /// ready pool for `.loadCoins`/`.needsReschedule`).
        public let vouchers: [Voucher]
        /// Coins selected for recycling (empty for `.ready`).
        public let coins: [Coin]
        /// The originally requested transfer amount.
        public let fullAmount: BigUInt

        public init(
            vouchers: [Voucher],
            coins: [Coin],
            fullAmount: BigUInt
        ) {
            self.vouchers = vouchers
            self.coins = coins
            self.fullAmount = fullAmount
        }
    }
}

// MARK: - Convenience

public extension ExternalPaymentPreview {
    var selection: Selection? {
        switch self {
        case let .ready(selection),
             let .loadCoins(selection),
             let .needsReschedule(_, selection):
            selection
        case .notEnoughBalance:
            nil
        }
    }

    var fullAmount: BigUInt { selection?.fullAmount ?? .zero }

    var isExecutable: Bool {
        switch self {
        case .ready,
             .loadCoins:
            true
        case .needsReschedule,
             .notEnoughBalance:
            false
        }
    }
}
