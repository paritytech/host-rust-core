import BigInt
import Coinage
import Foundation

/// Turns a classified ``CoinageHoldings`` snapshot into what the breakdown draws: the ordered
/// rows and the summary bar's three shares.
///
/// Pure and free of the presenter's state, so the ordering and the value weighting can be
/// exercised directly.
enum CoinageBreakdownFactory {
    /// A row before pricing: what it takes to order it and to draw it.
    struct Row: Equatable {
        let id: String
        let exponent: Int16
        /// Tie-break within one value: spendable coins, then vouchers, then held-back coins.
        let rank: Int
        let derivationIndex: DerivationIndex
        let status: CoinageHoldingViewModel.Status
    }

    /// Coins and vouchers interleaved into one list: by value descending, then by class, then by
    /// derivation index so equal holdings keep a stable order across refreshes.
    static func rows(from holdings: CoinageHoldings) -> [Row] {
        let coinRows = holdings.coins.map { holding in
            Row(
                id: "coin-\(holding.coin.derivationIndex)",
                exponent: holding.coin.exponent,
                rank: holding.isAvailableNow ? 0 : 2,
                derivationIndex: holding.coin.derivationIndex,
                status: .coin(
                    CoinStatusView.Model(
                        hopDots: holding.coin.hops.map(innerDots(for:)),
                        fungibility: holding.coin.recyclerFungibility,
                        isSpendable: holding.isAvailableNow
                    )
                )
            )
        }

        let voucherRows = holdings.vouchers.map { holding in
            Row(
                id: "voucher-\(holding.voucher.derivationIndex)",
                exponent: holding.voucher.exponent,
                rank: 1,
                derivationIndex: holding.voucher.derivationIndex,
                status: .voucher(
                    VoucherStatusView.Model(
                        maxFungibility: holding.voucher.maxRecyclerFungibility,
                        fungibility: holding.voucher.recyclerFungibility,
                        isUnloadable: holding.isAvailableNow
                    )
                )
            )
        }

        // Value is `unit * 2^exponent`, so ordering by exponent is exactly ordering by value.
        return (coinRows + voucherRows).sorted { lhs, rhs in
            if lhs.exponent != rhs.exponent {
                return lhs.exponent > rhs.exponent
            }

            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }

            return lhs.derivationIndex < rhs.derivationIndex
        }
    }

    /// Value-weighted split for the summary bar, bucketed exactly as the figures above it are:
    /// every holding lands in one bucket regardless of whether it is a coin or a voucher, so the
    /// three shares account for the whole total balance.
    static func composition(
        of holdings: CoinageHoldings,
        context: DenominationBreakdownContext
    ) -> CoinageCompositionBar.Model {
        let planks = planksByAvailability(of: holdings) {
            context.valueInPlanks(for: $0)
        }
        let total = planks.total

        guard total > 0 else { return .empty }

        // Scaled integer division keeps this exact for plank counts far beyond Double.
        func share(_ part: BigUInt) -> Double {
            let scale = BigUInt(1_000_000)
            return Double(part * scale / total) / Double(scale)
        }

        return CoinageCompositionBar.Model(
            availableNowShare: share(planks.availableNow),
            gainingPrivacyShare: share(planks.gainingPrivacy),
            pendingShare: share(planks.pending)
        )
    }

    /// Plank totals per bucket. A named type rather than a tuple, so the three stay labelled
    /// wherever they travel.
    private struct BucketPlanks {
        var availableNow = BigUInt(0)
        var gainingPrivacy = BigUInt(0)
        var pending = BigUInt(0)

        var total: BigUInt { availableNow + gainingPrivacy + pending }
    }

    private static func planksByAvailability(
        of holdings: CoinageHoldings,
        value: (Int16) -> BigUInt
    ) -> BucketPlanks {
        var planks = BucketPlanks()

        func add(_ availability: CoinageAvailability, _ amount: BigUInt) {
            switch availability {
            case .availableNow: planks.availableNow += amount
            case .gainingPrivacy: planks.gainingPrivacy += amount
            case .pending: planks.pending += amount
            }
        }

        for holding in holdings.coins {
            add(holding.availability, value(holding.coin.exponent))
        }

        for holding in holdings.vouchers {
            add(holding.availability, value(holding.voucher.exponent))
        }

        return planks
    }

    /// Inner dots for a hop: one per sibling it moved or was produced alongside.
    private static func innerDots(for hop: Hop) -> Int {
        switch hop {
        case let .transfer(bundleSize):
            CoinageStatusMetrics.innerDots(forCount: bundleSize)
        case let .split(fanout):
            CoinageStatusMetrics.innerDots(forCount: fanout)
        }
    }
}

/// The figures shown above the summary bar. The last three partition ``total``, and are the
/// three buckets the bar draws.
struct CoinageAmounts: Equatable {
    let total: Decimal
    let availableNow: Decimal
    let gainingPrivacy: Decimal
    let pending: Decimal

    static let zero = CoinageAmounts(total: 0, availableNow: 0, gainingPrivacy: 0, pending: 0)
}
