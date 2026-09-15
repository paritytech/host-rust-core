import Foundation
import SubstrateSdk
import BigInt

public struct Denomination: Equatable {
    public let exponent: Int16
}

public struct DenominationBreakdownContext: Equatable {
    // Base amount which is basically unit*2^0
    // when precision is 18 and unit is 10^16 - unit value is 0.01
    let unit: BigUInt
    let precision: Int16
    let maxExponent: Int16
    let minExponent: Int16

    func breakdown(amount: Decimal) -> [Denomination] {
        guard let planks = amount.toSubstrateAmount(precision: precision) else {
            return []
        }
        return breakdown(amountInPlanks: planks)
    }

    /// Converts a denomination back into its decimal currency amount.
    func amount(for denomination: Denomination) -> Decimal {
        amount(forExponent: denomination.exponent)
    }

    func amount(forExponent exponent: Int16) -> Decimal {
        let value = valueInPlanks(for: exponent)
        return .fromSubstrateAmount(value, precision: precision) ?? 0
    }

    /// Creates a new context with updated precision from the given asset.
    /// - Parameter asset: The asset providing the new decimal precision
    /// - Returns: A new context with the asset's precision
    func withChanging(asset: AssetProtocol) -> DenominationBreakdownContext {
        DenominationBreakdownContext(
            unit: unit,
            precision: asset.decimalPrecision,
            maxExponent: maxExponent,
            minExponent: minExponent
        )
    }

    /// Breaks a plank amount directly into denominations, skipping the Decimal conversion.
    func breakdown(amountInPlanks remaining: BigUInt) -> [Denomination] {
        var remaining = remaining
        var results: [Denomination] = []

        for exponent in stride(from: maxExponent, through: minExponent, by: -1) {
            let value = valueInPlanks(for: exponent)
            guard value > 0 else { continue }
            while remaining >= value {
                results.append(Denomination(exponent: exponent))
                remaining -= value
            }
        }

        return results
    }

    /// Converts a plank amount into its decimal currency amount using the asset precision. Public so
    /// display consumers can render ``CoinageBalance`` buckets without reaching for the precision.
    public func decimal(fromPlanks planks: Balance) -> Decimal {
        .fromSubstrateAmount(planks, precision: precision) ?? 0
    }

    /// Returns the plank value for a given denomination exponent: `unit * 2^exponent`.
    public func valueInPlanks(for exponent: Int16) -> BigUInt {
        if exponent >= 0 {
            // unit * 2^exponent
            unit << Int(exponent)
        } else {
            // unit / 2^abs(exponent)
            unit >> Int(abs(exponent))
        }
    }
}
