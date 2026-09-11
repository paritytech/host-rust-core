@testable import Coinage
import Foundation
import Testing

/// Pass-level behavior that the rule ladder (``CoinageRulesTests``) does not cover: DAG
/// propagation, submission ownership, and the compare-and-set write guard. Runs the real
/// `RecoveryPass` over a `FakeChainView`.
@Suite("Recovery Pass")
struct RecoveryPassTests {
    /// A finalized consumer proves the minter's output existed, so the pass promotes the minter to
    /// `finalizedSuccess` in the same pass — even though the ladder alone leaves it PENDING.
    @Test("Propagation promotes a minter when its consumer is finalized")
    func propagationPromotesMinterFromFinalizedConsumer() async throws {
        let store = MockCoinageTxRepository()
        let chain = FakeChainView(finalized: .fixture(150), best: .fixture(150))
        let watched = CoinageTrackingTxSet()

        let minter = CoinageTxEntry.fixture(outputs: [.coin(1, testKey(1))])
        let consumer = CoinageTxEntry.fixture(
            inputs: [.coin(.own(1, testKey(1)))],
            outputs: [.coin(2, testKey(2))],
            status: .finalizedSuccess
        )
        try await store.register(minter)
        try await store.register(consumer)

        let pass = RecoveryPass(store: store, chainFactory: chain, watched: watched, logger: nil)
        await pass.run()

        let promoted = try await store.getEntry(id: minter.id)
        #expect(promoted?.status == .finalizedSuccess)
    }

    /// An entry a submission owns is skipped: the pass must never decide an entry a live tracker is
    /// still driving.
    @Test("A submission-owned entry gets no verdict")
    func submissionOwnedEntrySkipped() async throws {
        let store = MockCoinageTxRepository()
        let chain = FakeChainView(finalized: .fixture(150), best: .fixture(150))
        let watched = CoinageTrackingTxSet()

        let minter = CoinageTxEntry.fixture(outputs: [.coin(1, testKey(1))])
        let consumer = CoinageTxEntry.fixture(inputs: [.coin(.own(1, testKey(1)))], status: .finalizedSuccess)
        try await store.register(minter)
        try await store.register(consumer)
        watched.take(minter.id)

        let pass = RecoveryPass(store: store, chainFactory: chain, watched: watched, logger: nil)
        await pass.run()

        // Propagation would otherwise have promoted it; ownership keeps it untouched.
        let fetched = try await store.getEntry(id: minter.id)
        #expect(fetched?.status == .pending)
    }

    /// A pass reading nothing decidable ends before pinning a view — a settled ledger costs nothing.
    @Test("A settled ledger does not pin a chain view")
    func settledLedgerDoesNotPin() async throws {
        let store = MockCoinageTxRepository()
        let chain = FakeChainView(finalized: .fixture(150), best: .fixture(150))
        let watched = CoinageTrackingTxSet()

        try await store.register(CoinageTxEntry.fixture(outputs: [.coin(1, testKey(1))], status: .finalizedSuccess))

        let pass = RecoveryPass(store: store, chainFactory: chain, watched: watched, logger: nil)
        await pass.run()

        #expect(chain.pinCount == 0)
    }

    // MARK: - Compare-and-set write guard

    @Test("updateTxStatus writes only while the observed status still holds")
    func compareAndSetRejectsMovedStatus() async throws {
        let store = MockCoinageTxRepository()
        let entry = CoinageTxEntry.fixture(outputs: [.coin(1, testKey(1))])
        try await store.register(entry)

        // The status moved to pendingSuccess after the verdict was formed against pending.
        try await store.updateStatus(entry.id, to: .pendingSuccess)

        let wrote = try await store.updateTxStatus(
            for: entry.id,
            expectedCurrentStatus: .pending,
            verdict: Verdict(status: .finalizedSuccess, successDetectedAt: nil)
        )

        #expect(wrote == false)
        let fetched = try await store.getEntry(id: entry.id)
        #expect(fetched?.status == .pendingSuccess)
    }

    @Test("updateTxStatus does not overwrite a terminal entry")
    func compareAndSetLeavesTerminalUntouched() async throws {
        let store = MockCoinageTxRepository()
        let entry = CoinageTxEntry.fixture(outputs: [.coin(1, testKey(1))], status: .finalizedSuccess)
        try await store.register(entry)

        let wrote = try await store.updateTxStatus(
            for: entry.id,
            expectedCurrentStatus: .finalizedSuccess,
            verdict: Verdict(status: .failure, successDetectedAt: nil)
        )

        #expect(wrote == false)
        let fetched = try await store.getEntry(id: entry.id)
        #expect(fetched?.status == .finalizedSuccess)
    }
}
