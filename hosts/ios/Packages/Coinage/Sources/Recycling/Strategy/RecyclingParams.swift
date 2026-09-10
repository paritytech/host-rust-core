import Foundation
import SubstrateSdk
import BigInt

/// Preset parameters resolved from a ``RecyclingStrategyType``. One parametric policy is driven by
/// these three knobs, so later releases can open intermediate points on the axis without a rewrite.
public struct RecyclingParams: Equatable {
    /// Share of total balance acceptable to hold *unavailable* while recycling. A ceiling, not a
    /// target — it exists so more than one coin can recycle at once.
    public let maxUnavailableBalance: BigRational

    /// Age below which recycling is not considered at all.
    public let minRecyclingAge: Int16

    /// How full a ring must be before a recycled voucher counts usable again — the knob that
    /// produces the spendability delay.
    public let requiredRingFill: BigRational

    /// Whether gaining-privacy balance may be spent behind a confirmation.
    public let allowsConfirmedSpend: Bool

    public init(
        maxUnavailableBalance: BigRational,
        minRecyclingAge: Int16,
        requiredRingFill: BigRational,
        allowsConfirmedSpend: Bool
    ) {
        self.maxUnavailableBalance = maxUnavailableBalance
        self.minRecyclingAge = minRecyclingAge
        self.requiredRingFill = requiredRingFill
        self.allowsConfirmedSpend = allowsConfirmedSpend
    }
}
