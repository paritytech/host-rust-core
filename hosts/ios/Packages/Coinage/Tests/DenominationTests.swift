import Testing
import Foundation
import BigInt
@testable import Coinage

struct DenominationTests {
    // 1 cent ($0.01) at 18 decimals = 10^16 planks
    let context = DenominationBreakdownContext(
        unit: BigUInt(10).power(16),
        precision: 18,
        maxExponent: 7,
        minExponent: 0
    )

    @Test("Amount property calculates the correct power of 2 for valid exponents")
    func amountProperty() {
        // unit * 2^7 = 0.01 * 128 = 1.28
        #expect(context.amount(for: Denomination(exponent: 7)) == 1.28)
        // unit * 2^4 = 0.01 * 16 = 0.16
        #expect(context.amount(for: Denomination(exponent: 4)) == 0.16)
        // unit * 2^0 = 0.01 * 1 = 0.01
        #expect(context.amount(for: Denomination(exponent: 0)) == 0.01)
    }

    @Test("Breakdown correctly decomposes a whole number into powers of 2 (Greedy)")
    func breakdownWholeNumber() {
        // Target: $1.50 = 150 cents
        // 150 = 128 (2^7) + 16 (2^4) + 4 (2^2) + 2 (2^1)
        let denominations = context.breakdown(amount: 1.50)
        let exponents = denominations.map(\.exponent)

        #expect(exponents == [7, 4, 2, 1])
    }

    @Test("Breakdown handles amounts that are multiples of the base unit")
    func breakdownCents() {
        // $0.07 = 7 cents
        // 7 = 4 (2^2) + 2 (2^1) + 1 (2^0)
        let denominations = context.breakdown(amount: 0.07)
        let exponents = denominations.map(\.exponent)

        #expect(exponents == [2, 1, 0])
    }

    @Test("Breakdown handles amounts requiring multiple units of the maximum denomination")
    func breakdownMultipleMaxUnits() {
        // $2.56 = 256 cents
        // 256 = 128 (2^7) + 128 (2^7)
        let denominations = context.breakdown(amount: 2.56)
        let exponents = denominations.map(\.exponent)

        #expect(exponents == [7, 7])
    }

    @Test("Breakdown ignores remainders smaller than the minimum denomination ($0.01)")
    func breakdownRemainderHandling() {
        // $0.015 = 1 cent represented (2^0), 0.5 cents ignored because minExponent is 0
        let denominations = context.breakdown(amount: 0.015)
        let exponents = denominations.map(\.exponent)

        #expect(exponents == [0])
    }

    @Test("Breakdown returns an empty list for values below the unit")
    func breakdownVerySmallAmount() {
        // $0.005 is smaller than the unit $0.01 (minExponent 0)
        let denominations = context.breakdown(amount: 0.005)
        #expect(denominations.isEmpty)

        let zeroDenominations = context.breakdown(amount: 0)
        #expect(zeroDenominations.isEmpty)
    }
}
