import Foundation
import BigInt
import SubstrateSdkExt
import SubstrateSdk

/// The single recycling policy. Both decorators wrap an instance of this.
public struct ParametricRecyclingStrategy: CoinRecyclingStrategyProtocol {
    private let params: RecyclingParams

    public init(params: RecyclingParams) {
        self.params = params
    }

    public func evaluate(
        coins: [Coin],
        snapshot: RecyclingSnapshot,
        context: DenominationBreakdownContext
    ) -> RecyclingVerdicts {
        let budget = params.maxUnavailableBalance.mul(value: snapshot.total)
        var unavailable = snapshot.unavailable
        var verdicts = RecyclingVerdicts()

        for coin in coins.sorted(by: Self.olderFirst) {
            // Headroom, not fit: while anything is left in the budget the next coin is admitted even
            // if it overshoots, so a coin larger than the whole budget still recycles instead of
            // waiting for the forced age. A zero budget admits nothing (`unavailable < 0` is never true).
            let gated = coin.ageOrDefault >= params.minRecyclingAge && unavailable < budget
            if gated {
                unavailable += context.valueInPlanks(for: coin.exponent)
                verdicts[coin.derivationIndex] = .toRecycle
            } else {
                verdicts[coin.derivationIndex] = .allowUse
            }
        }

        return verdicts
    }

    /// Oldest first, ties broken by derivation index. Budget is consumed in this order, so equal-age coins
    /// need a stable tiebreaker or a coin can flap between spendable and held across ticks (`sorted(by:)` is
    /// not a stable sort).
    private static func olderFirst(_ lhs: Coin, _ rhs: Coin) -> Bool {
        if lhs.ageOrDefault != rhs.ageOrDefault {
            return lhs.ageOrDefault > rhs.ageOrDefault
        }
        return lhs.derivationIndex < rhs.derivationIndex
    }

    public func isVoucherUsable(_ voucher: Voucher, context: VoucherUsabilityContext) -> Bool {
        guard case let .inRecycler(recycler) = voucher.remoteState else { return false }

        guard params.requiredRingFill > .withInt(0) else {
            // ring state does not matter, unlock voucher
            return true
        }

        let members = BigUInt(recycler.membersCount)

        // members >= requiredRingFill * capacity. `mul(value:)` returns the required member count as a
        // BigUInt, so both sides are BigUInt. An unresolved capacity reads as never full.
        let ringFilled =
            if let capacity = context.capacity(for: voucher.exponent) {
                members >= params.requiredRingFill.mul(value: BigUInt(capacity))
            } else {
                false
            }

        // Below a full ring the random unload delay is an acceptable substitute for anonymity-set
        // size; at 100% nothing but a full ring will do.
        let delayElapsed = params.requiredRingFill < .full && voucher.readyAt < context.now

        return ringFilled || delayElapsed
    }

    public func allowsConfirmedSpend() -> Bool {
        params.allowsConfirmedSpend
    }
}
