import Coinage
import Foundation
import Testing

/// Ownership and status-write invariants the tracker relies on: one-shot ownership via
/// ``CoinageTrackingTxSet``, and the repository's compare-and-set / field-write guards.
@Suite("Submission Watcher")
struct SubmissionWatcherTests {
    @Test("Ownership taken once and released exactly once")
    func ownershipOneShotRelease() async throws {
        let watched = CoinageTrackingTxSet()
        let id = UUID()

        watched.take(id)
        #expect(watched.isWatched(id))

        #expect(watched.release(id))
        #expect(!watched.isWatched(id))

        // Release is one-shot, so a caller can keep its release side effects one-shot too.
        #expect(!watched.release(id))
    }

    @Test("Releasing ownership does not itself change the entry")
    func releaseLeavesEntryUnchanged() async throws {
        let store = MockCoinageTxRepository()
        let watched = CoinageTrackingTxSet()
        let id = UUID()

        try await store.register(.fixture(id: id, outputs: [.coin(1, testKey(1))]))

        watched.take(id)
        _ = watched.release(id)

        let fetched = try await store.getEntry(id: id)
        #expect(fetched?.status == .pending)
        // txHash is fixed at registration and never rewritten by release.
        #expect(fetched?.txHash == Data(repeating: 0xAB, count: 32))
    }

    @Test("A finalized verdict on an already-failed entry is rejected")
    func finalizedOnFailedRejected() async throws {
        let store = MockCoinageTxRepository()
        let id = UUID()

        try await store.register(.fixture(id: id, outputs: [.coin(1, testKey(1))]))
        try await store.updateStatus(id, to: .failure)

        let wrote = try await store.updateTxStatus(
            for: id,
            expectedCurrentStatus: .failure,
            verdict: Verdict(status: .finalizedSuccess, successDetectedAt: nil)
        )

        #expect(wrote == false)
        let fetched = try await store.getEntry(id: id)
        #expect(fetched?.status == .failure)
    }
}
