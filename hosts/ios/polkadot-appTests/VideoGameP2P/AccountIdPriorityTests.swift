@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

struct AccountIdPriorityTests {
    private func makeAccountId(_ bytes: [UInt8]) -> AccountId {
        Data(bytes + Array(repeating: UInt8(0), count: max(0, 32 - bytes.count)))
    }

    @Test("Lower byte value precedes higher byte value")
    func lowerPrecedesHigher() {
        let lower = makeAccountId([0x01])
        let higher = makeAccountId([0x02])

        #expect(lower.precedes(higher) == true)
        #expect(higher.precedes(lower) == false)
    }

    @Test("Identical account IDs do not precede each other")
    func identicalDoNotPrecede() {
        let accountId = makeAccountId([0x05, 0x05])

        #expect(accountId.precedes(accountId) == false)
    }

    @Test("Comparison is lexicographic on first differing byte")
    func lexicographicOnFirstDifference() {
        let a = makeAccountId([0x01, 0x02, 0xFF])
        let b = makeAccountId([0x01, 0x03, 0x00])

        // First byte equal, second byte: 0x02 < 0x03
        #expect(a.precedes(b) == true)
        #expect(b.precedes(a) == false)
    }

    @Test("Role determination is consistent between two peers")
    func roleConsistency() {
        let local = makeAccountId([0x0A])
        let remote = makeAccountId([0x0B])

        let localIsInitiator = local.precedes(remote)
        let remoteIsInitiator = remote.precedes(local)

        // Exactly one should be initiator
        #expect(localIsInitiator != remoteIsInitiator)
    }
}
