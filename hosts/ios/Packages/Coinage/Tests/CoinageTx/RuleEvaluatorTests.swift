import Coinage
import Foundation
import Testing

/// The rule ladder. The evaluator is impure — its last rule searches block bodies through the
/// pinned view — and pure over the earlier state, so the table is exercised by handing it a
/// ``ChainEvidence`` and a ``CoinageEntryDag`` directly.
@Suite("Coinage Rules")
struct CoinageRulesTests {
    private let view = FakeChainView()

    // MARK: Rule 0 — recorded inclusion

    @Test("Rule 0 finalizes when the recorded block is canonical and at or below the finalized head")
    func rule0FinalizesCanonicalAtOrBelowFinalized() async throws {
        let entry = entry(outputs: [coinOut], successDetectedAt: block(120))

        let outcome = await evaluate(entry, evidence(finalizedNumber: 130, recordedBlockStillCanonical: true))

        try #require(outcome.verdict?.status == .finalizedSuccess)
    }

    @Test("Rule 0 holds at PENDING_SUCCESS while the recorded block is above the finalized head")
    func rule0HoldsPendingSuccessAboveFinalized() async throws {
        let entry = entry(outputs: [coinOut], successDetectedAt: block(140))

        let outcome = await evaluate(entry, evidence(finalizedNumber: 130, recordedBlockStillCanonical: true))

        try #require(outcome.verdict?.status == .pendingSuccess)
    }

    @Test("Rule 0 clause 1 re-records the best head when execution is still visible there")
    func rule0Clause1ReRecordsBestWhenVisible() async throws {
        let entry = entry(outputs: [coinOut], successDetectedAt: block(120))

        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: 130, presentAtBest: [coinOut.publicKey], recordedBlockStillCanonical: false)
        )

        let verdict = try #require(outcome.verdict)
        #expect(verdict.status == .pendingSuccess)
        #expect(verdict.successDetectedAt == bestBlock)
    }

    @Test("Rule 0 clause 1 demotes to PENDING and clears the record when nothing is visible any more")
    func rule0Clause1DemotesAndClears() async throws {
        let entry = entry(outputs: [coinOut], successDetectedAt: block(120))

        let outcome = await evaluate(entry, evidence(finalizedNumber: 130, recordedBlockStillCanonical: false))

        let verdict = try #require(outcome.verdict)
        #expect(verdict.status == .pending)
        #expect(verdict.successDetectedAt == nil)
    }

    @Test("Rule 0 aborts the entry when the canonicality read failed")
    func rule0AbortsWhenCanonicalityUnread() async {
        let entry = entry(outputs: [coinOut], successDetectedAt: block(120))

        let outcome = await evaluate(entry, evidence(finalizedNumber: 130, recordedBlockStillCanonical: nil))

        #expect(outcome == .undecided)
    }

    // MARK: Rules 1 and 2 — visible execution

    @Test("Rule 1 wins over Rule 2 on the same evidence")
    func rule1WinsOverRule2() async throws {
        let entry = entry(outputs: [coinOut])

        let outcome = await evaluate(
            entry,
            evidence(presentAtFinalized: [coinOut.publicKey], presentAtBest: [coinOut.publicKey])
        )

        try #require(outcome.verdict?.status == .finalizedSuccess)
    }

    @Test("Rule 2 records the best head so the outputs keep optimistic selectability")
    func rule2RecordsBestHead() async throws {
        let entry = entry(outputs: [coinOut])

        let outcome = await evaluate(entry, evidence(presentAtBest: [coinOut.publicKey]))

        let verdict = try #require(outcome.verdict)
        #expect(verdict.status == .pendingSuccess)
        #expect(verdict.successDetectedAt == bestBlock)
    }

    @Test("an unloaded voucher input counts as execution")
    func unloadedVoucherInputIsExecution() async throws {
        let entry = entry(inputs: [voucherIn])

        let outcome = await evaluate(entry, evidence(unloadedAtFinalized: [voucherIn.publicKey]))

        try #require(outcome.verdict?.status == .finalizedSuccess)
    }

    // MARK: Rules 3 and 4 — mortality expired

    @Test("Rule 3 fails the entry when an untouched output is absent after mortality")
    func rule3FailsUntouchedAbsentAfterMortality() async throws {
        let entry = entry(outputs: [coinOut])

        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: mortalityEnd + 1, absentAtFinalized: [coinOut.publicKey])
        )

        try #require(outcome.verdict?.status == .failure)
    }

    @Test("Rule 3 does not fire before mortality has expired")
    func rule3DoesNotFireBeforeMortality() async throws {
        let entry = entry(outputs: [coinOut])

        let outcome = await evaluate(
            entry,
            evidence(
                finalizedNumber: mortalityEnd,
                absentAtFinalized: [coinOut.publicKey],
                absentAtBest: [coinOut.publicKey]
            )
        )

        try #require(outcome.verdict?.status == .pending)
    }

    @Test("Rule 4 fails the entry when an input is still available after mortality")
    func rule4FailsAvailableInputAfterMortality() async throws {
        let entry = entry(inputs: [coinIn], outputs: [coinOut])

        // The output is unreadable, so Rule 3 cannot fire and Rule 4 is reached.
        let outcome = await evaluate(
            entry,
            evidence(
                finalizedNumber: mortalityEnd + 1,
                presentAtFinalized: [coinIn.publicKey],
                unreadable: [coinOut.publicKey]
            )
        )

        try #require(outcome.verdict?.status == .failure)
    }

    @Test("Rule 4 does not fire before mortality has expired")
    func rule4DoesNotFireBeforeMortality() async throws {
        let entry = entry(inputs: [coinIn], outputs: [coinOut])

        let outcome = await evaluate(
            entry,
            evidence(
                finalizedNumber: mortalityEnd,
                presentAtFinalized: [coinIn.publicKey],
                presentAtBest: [coinIn.publicKey],
                unreadable: [coinOut.publicKey]
            )
        )

        try #require(outcome.verdict?.status == .pending)
    }

    // MARK: Rules 5 and 6 — our own coins gone

    @Test("Rule 5 finalizes when every own-coin input is gone at the finalized head")
    func rule5FinalizesOwnCoinsGone() async throws {
        let minter = finalizedMinter(coinIn)
        let entry = entry(inputs: [coinIn])

        let outcome = await evaluate(
            entry,
            evidence(absentAtFinalized: [coinIn.publicKey], absentAtBest: [coinIn.publicKey]),
            dag: dag(minter, entry)
        )

        try #require(outcome.verdict?.status == .finalizedSuccess)
    }

    @Test("Rule 6 does not fire on an unexecuted entry — a registered unincluded split stays PENDING")
    func rule6DoesNotFireOnUnexecuted() async throws {
        let minter = finalizedMinter(coinIn)
        let entry = entry(inputs: [coinIn], outputs: [coinOut])

        // The input is still there at both heads: the split never executed.
        let outcome = await evaluate(
            entry,
            evidence(
                presentAtFinalized: [coinIn.publicKey],
                absentAtFinalized: [coinOut.publicKey],
                presentAtBest: [coinIn.publicKey],
                absentAtBest: [coinOut.publicKey]
            ),
            dag: dag(minter, entry)
        )

        try #require(outcome.verdict?.status == .pending)
    }

    @Test("ownCoinInputs declines when an input has ever carried a handoff mark")
    func ownCoinInputsDeclinesOnHandoff() async throws {
        let minter = finalizedMinter(coinIn)
        let entry = entry(inputs: [coinIn])

        let outcome = await evaluate(
            entry,
            evidence(absentAtFinalized: [coinIn.publicKey], absentAtBest: [coinIn.publicKey]),
            dag: dag(minter, entry, handedOff: [coinIn.publicKey])
        )

        // Falls through to the search rather than reading absence as consumption.
        try #require(outcome.verdict?.status == .pending)
        assertReachedSearch()
    }

    @Test("ownCoinInputs declines while the input minter's own window is still open")
    func ownCoinInputsDeclinesWhileMinterWindowOpen() async throws {
        let minter = finalizedMinter(coinIn, checkpointNumber: 200)
        let entry = entry(inputs: [coinIn])

        let outcome = await evaluate(
            entry,
            evidence(absentAtFinalized: [coinIn.publicKey], absentAtBest: [coinIn.publicKey]),
            dag: dag(minter, entry)
        )

        try #require(outcome.verdict?.status == .pending)
        assertReachedSearch()
    }

    @Test("a failed read never satisfies absent, so Rule 5 cannot fire on it")
    func failedReadNeverSatisfiesAbsent() async throws {
        let minter = finalizedMinter(coinIn)
        let entry = entry(inputs: [coinIn])

        let outcome = await evaluate(
            entry,
            evidence(unreadable: [coinIn.publicKey]),
            dag: dag(minter, entry)
        )

        try #require(outcome.verdict?.status == .pending)
        assertReachedSearch()
    }

    // MARK: Rule 7 — body search

    @Test("Rule 7 finalizes on a successful dispatch in the searched block")
    func rule7FinalizesOnSuccess() async throws {
        let entry = entry(inputs: [receivedIn])

        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: mortalityEnd + 1, unreadable: [receivedIn.publicKey]),
            search: .foundSucceeded(block(120))
        )

        try #require(outcome.verdict?.status == .finalizedSuccess)
    }

    @Test("Rule 7 fails on a failed dispatch — inclusion is not success")
    func rule7FailsOnFailedDispatch() async throws {
        let entry = entry(inputs: [receivedIn])

        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: mortalityEnd + 1, unreadable: [receivedIn.publicKey]),
            search: .foundFailed(block(120))
        )

        try #require(outcome.verdict?.status == .failure)
    }

    @Test("Rule 7 leaves the entry PENDING when the outcome could not be read")
    func rule7PendingWhenOutcomeUnreadable() async throws {
        let entry = entry(inputs: [receivedIn])

        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: mortalityEnd + 1, unreadable: [receivedIn.publicKey]),
            search: .foundOutcomeUnreadable(block(120))
        )

        try #require(outcome.verdict?.status == .pending)
    }

    @Test("Rule 7 fails only once the whole window was read and mortality has expired")
    func rule7FailsWhenWholeWindowReadAndMortalityExpired() async throws {
        let entry = entry(inputs: [receivedIn])

        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: mortalityEnd + 1, unreadable: [receivedIn.publicKey]),
            search: .notFoundWindowComplete
        )

        try #require(outcome.verdict?.status == .failure)
    }

    @Test("a partially read window leaves the entry PENDING")
    func rule7PartialWindowStaysPending() async throws {
        let entry = entry(inputs: [receivedIn])

        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: mortalityEnd + 1, unreadable: [receivedIn.publicKey]),
            search: .incomplete
        )

        try #require(outcome.verdict?.status == .pending)
    }

    // MARK: Ladder guards surfaced by the mutation sweep

    @Test("Rule 3 respects the handoff guard: a handed-off output is not read as freely gone")
    func rule3RespectsHandoffOnOutput() async throws {
        let minter = finalizedMinter(coinIn)
        let entry = entry(inputs: [coinIn], outputs: [coinOut])

        // The output is absent past mortality, but handed off — so it has a potential consumer and Rule 3
        // must not fail on it. The proven-own-coin input then finalizes the entry via Rule 5.
        let outcome = await evaluate(
            entry,
            evidence(
                finalizedNumber: mortalityEnd + 1,
                absentAtFinalized: [coinIn.publicKey, coinOut.publicKey],
                absentAtBest: [coinIn.publicKey, coinOut.publicKey]
            ),
            dag: dag(minter, entry, handedOff: [coinOut.publicKey])
        )

        try #require(outcome.verdict?.status == .finalizedSuccess)
    }

    @Test("Rule 3 respects a live consumer: an output a live entry still claims is not read as gone")
    func rule3RespectsLiveConsumerOnOutput() async throws {
        let minter = finalizedMinter(coinIn)
        // Build the consumer before shadowing the `entry` factory with the local `entry` below.
        let consumer = entry(id: Self.consumerId, inputs: [coinOut.asInput])
        let entry = entry(inputs: [coinIn], outputs: [coinOut])

        let outcome = await evaluate(
            entry,
            evidence(
                finalizedNumber: mortalityEnd + 1,
                absentAtFinalized: [coinIn.publicKey, coinOut.publicKey],
                absentAtBest: [coinIn.publicKey, coinOut.publicKey]
            ),
            dag: dag(minter, entry, consumer)
        )

        try #require(outcome.verdict?.status == .finalizedSuccess)
    }

    @Test("Rule 6 requires proven own coins: a received-coin input is not promoted to PENDING_SUCCESS")
    func rule6RequiresProvenOwnCoins() async throws {
        let entry = entry(inputs: [receivedIn])

        // Inside the window, the input exists at the finalized head and is gone at the best head — the
        // shape Rule 6 fires on, but only for proven own coins. A received coin must reach the search.
        let outcome = await evaluate(
            entry,
            evidence(presentAtFinalized: [receivedIn.publicKey], absentAtBest: [receivedIn.publicKey])
        )

        try #require(outcome.verdict?.status == .pending)
    }

    @Test("Rule 4b holds only inside the window: past mortality an available input reaches the search")
    func rule4bHoldsOnlyInsideWindow() async throws {
        let entry = entry(inputs: [receivedIn])

        // Available at the best head but gone at the finalized head, past mortality. Rule 4 cannot fire
        // (not available at F), and 4b must not hold it PENDING past the window — the search decides.
        let outcome = await evaluate(
            entry,
            evidence(
                finalizedNumber: mortalityEnd + 1,
                absentAtFinalized: [receivedIn.publicKey],
                presentAtBest: [receivedIn.publicKey]
            ),
            search: .notFoundWindowComplete
        )

        try #require(outcome.verdict?.status == .failure)
    }

    @Test("Rule 3b holds only inside the window: past mortality an absent output reaches the search")
    func rule3bHoldsOnlyInsideWindow() async throws {
        let entry = entry(outputs: [coinOut])

        // Unreadable at the finalized head (so Rule 3 cannot fire) yet absent at the best head, past
        // mortality. 3b must not hold it PENDING past the window — the completed search fails it.
        let outcome = await evaluate(
            entry,
            evidence(finalizedNumber: mortalityEnd + 1, absentAtBest: [coinOut.publicKey]),
            search: .notFoundWindowComplete
        )

        try #require(outcome.verdict?.status == .failure)
    }
}

// MARK: - Harness

private extension CoinageRulesTests {
    var coinIn: CoinageTxInput { .coin(.own(1, testKey(1))) }
    var coinOut: OwnAsset { .coin(2, testKey(2)) }
    var voucherIn: CoinageTxInput { .recyclerVoucher(3, testKey(3)) }
    var receivedIn: CoinageTxInput { .coin(.received(Data([4]))) }

    static let checkpointNumber: UInt32 = 100
    static let mortality: UInt32 = 64
    var mortalityEnd: UInt32 { Self.checkpointNumber + Self.mortality }

    var bestBlock: BlockRef { block(200) }

    func block(_ number: UInt32) -> BlockRef {
        BlockRef(number: number, hash: Data("block\(number)".utf8))
    }

    func evaluate(
        _ entry: CoinageTxEntry,
        _ evidence: ChainEvidence,
        dag: CoinageEntryDag? = nil,
        search: BodySearchOutcome = .incomplete
    ) async -> RuleOutcome {
        view.setBodySearchResponse(entry.txHash, to: search)
        return await RuleEvaluator().evaluate(
            entry: entry,
            dag: dag ?? self.dag(entry),
            evidence: evidence,
            view: view
        )
    }

    /// The ladder reached the last rule instead of deciding on state alone.
    func assertReachedSearch() {
        #expect(!view.searchedHashes.isEmpty)
    }

    func dag(_ entries: CoinageTxEntry..., handedOff: Set<PublicKey> = []) -> CoinageEntryDag {
        CoinageEntryDag(entries: entries, handedOff: handedOff)
    }

    /// A finalized entry that minted `input`'s asset long enough ago that its window has closed.
    func finalizedMinter(_ input: CoinageTxInput, checkpointNumber: UInt32 = 0) -> CoinageTxEntry {
        entry(
            id: Self.minterId,
            outputs: [input.ownAsset ?? .coin(0, testKey(0))],
            status: .finalizedSuccess,
            checkpointNumber: checkpointNumber
        )
    }

    func entry(
        id: CoinageTxId = CoinageRulesTests.entryId,
        inputs: [CoinageTxInput] = [],
        outputs: [OwnAsset] = [],
        status: CoinageTxStatus = .pending,
        successDetectedAt: BlockRef? = nil,
        checkpointNumber: UInt32 = CoinageRulesTests.checkpointNumber
    ) -> CoinageTxEntry {
        CoinageTxEntry(
            id: id,
            inputs: inputs,
            outputs: outputs,
            txHash: Data("tx\(id.uuidString)".utf8),
            checkpoint: BlockRef(number: checkpointNumber, hash: Data("checkpoint".utf8)),
            mortality: Self.mortality,
            successDetectedAt: successDetectedAt,
            status: status
        )
    }

    static let entryId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let minterId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let consumerId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    /// Builds `ChainEvidence` from identifier sets. An identifier in `unreadable` appears in no map
    /// — a failed read — so every predicate over it is false.
    func evidence(
        finalizedNumber: UInt32 = 150,
        presentAtFinalized: [PublicKey] = [],
        absentAtFinalized: [PublicKey] = [],
        presentAtBest: [PublicKey] = [],
        absentAtBest: [PublicKey] = [],
        unloadedAtFinalized: [PublicKey] = [],
        unreadable: [PublicKey] = [],
        recordedBlockStillCanonical: Bool? = nil
    ) -> ChainEvidence {
        func presence(_ present: [PublicKey], _ absent: [PublicKey]) -> [PublicKey: ChainPresence] {
            var result: [PublicKey: ChainPresence] = [:]
            for key in present where !unreadable.contains(key) {
                result[key] = .present
            }
            for key in absent where !unreadable.contains(key) {
                result[key] = .absent
            }
            return result
        }

        let alias = Dictionary(uniqueKeysWithValues: unloadedAtFinalized.map { ($0, AliasRead.unloaded) })

        return ChainEvidence(
            finalized: block(finalizedNumber),
            best: bestBlock,
            presenceAtFinalized: presence(presentAtFinalized, absentAtFinalized),
            presenceAtBest: presence(presentAtBest, absentAtBest),
            aliasAtFinalized: alias,
            aliasAtBest: alias,
            recordedBlockStillCanonical: recordedBlockStillCanonical
        )
    }
}

private extension RuleOutcome {
    var verdict: Verdict? {
        if case let .decided(verdict) = self { verdict } else { nil }
    }
}
