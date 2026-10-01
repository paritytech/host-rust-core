import Foundation
import Testing

@testable import polkadot_app

@Suite("Coinage amounts")
struct CoinageAmountsTests {
    @Test("Everything ready: the total already is the ready amount")
    func allReady() {
        let amounts = CoinageAmounts(total: 45, availableNow: 45, gainingPrivacy: 0, pending: 0)
        #expect(amounts.hasFundsNotReady == false)
    }

    @Test("Clearing funds are not ready")
    func clearing() {
        let amounts = CoinageAmounts(total: 45, availableNow: 40, gainingPrivacy: 5, pending: 0)
        #expect(amounts.hasFundsNotReady)
    }

    @Test("Pending funds right after a top-up are not ready")
    func pendingAfterTopUp() {
        let amounts = CoinageAmounts(total: 45, availableNow: 40, gainingPrivacy: 0, pending: 5)
        #expect(amounts.hasFundsNotReady)
    }

    @Test("Both buckets at once are not ready")
    func clearingAndPending() {
        let amounts = CoinageAmounts(total: 45, availableNow: 30, gainingPrivacy: 10, pending: 5)
        #expect(amounts.hasFundsNotReady)
    }

    @Test("Zero holdings are treated as ready")
    func zero() {
        #expect(CoinageAmounts.zero.hasFundsNotReady == false)
    }
}
