package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery

import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.ExtrinsicOutcome
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.OwnAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageAssetKind
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainView
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerEntry
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.TransactionSearchResult
import io.paritytech.polkadotapp.test_shared.anyLong
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify

private const val CHECKPOINT_NUMBER = 100L
private const val MORTALITY = 64L
private const val MORTALITY_END = CHECKPOINT_NUMBER + MORTALITY

class CoinageRulesTest {
    // ---- Rule 0 — recorded inclusion ----

    @Test
    fun `Rule 0 finalizes when the recorded block is canonical and at or below the finalized head`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut), successDetectedAt = block(120))

        val outcome = evaluate(
            entry,
            evidence(finalizedNumber = 130, recordedBlockStillCanonical = true),
        )

        assertDecided(CoinageTransactionStatus.FINALIZED_SUCCESS, outcome)
    }

    @Test
    fun `Rule 0 holds at PENDING_SUCCESS while the recorded block is above the finalized head`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut), successDetectedAt = block(140))

        val outcome = evaluate(
            entry,
            evidence(finalizedNumber = 130, recordedBlockStillCanonical = true),
        )

        assertDecided(CoinageTransactionStatus.PENDING_SUCCESS, outcome)
    }

    @Test
    fun `Rule 0 clause 1 re-records the best head when execution is still visible there`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut), successDetectedAt = block(120))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = 130,
                recordedBlockStillCanonical = false,
                presentAtBest = setOf(coinOut),
            ),
        )

        val decided = assertDecided(CoinageTransactionStatus.PENDING_SUCCESS, outcome)
        assertEquals(BEST_BLOCK, decided.verdict.successDetectedAt)
    }

    @Test
    fun `Rule 0 clause 1 demotes to PENDING and clears the record when nothing is visible any more`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut), successDetectedAt = block(120))

        val outcome = evaluate(
            entry,
            evidence(finalizedNumber = 130, recordedBlockStillCanonical = false),
        )

        val decided = assertDecided(CoinageTransactionStatus.PENDING, outcome)
        assertEquals(null, decided.verdict.successDetectedAt)
    }

    @Test
    fun `Rule 0 aborts the entry when the canonicality read failed`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut), successDetectedAt = block(120))

        val outcome = evaluate(entry, evidence(finalizedNumber = 130, recordedBlockStillCanonical = null))

        assertEquals(RuleOutcome.Undecided, outcome)
    }

    // ---- Rules 1 and 2 — visible execution ----

    @Test
    fun `Rule 1 wins over Rule 2 on the same evidence`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut))

        val outcome = evaluate(
            entry,
            evidence(presentAtFinalized = setOf(coinOut), presentAtBest = setOf(coinOut)),
        )

        assertDecided(CoinageTransactionStatus.FINALIZED_SUCCESS, outcome)
    }

    @Test
    fun `Rule 2 records the best head so the outputs keep optimistic selectability`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut))

        val outcome = evaluate(entry, evidence(presentAtBest = setOf(coinOut)))

        val decided = assertDecided(CoinageTransactionStatus.PENDING_SUCCESS, outcome)
        assertEquals(BEST_BLOCK, decided.verdict.successDetectedAt)
    }

    @Test
    fun `an unloaded voucher input counts as execution`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(voucherIn))

        val outcome = evaluate(entry, evidence(unloadedAtFinalized = setOf(voucherIn)))

        assertDecided(CoinageTransactionStatus.FINALIZED_SUCCESS, outcome)
    }

    // ---- Rules 3 and 4 — mortality expired ----

    @Test
    fun `Rule 3 fails the entry when an untouched output is absent after mortality`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut))

        val outcome = evaluate(
            entry,
            evidence(finalizedNumber = MORTALITY_END + 1, absentAtFinalized = setOf(coinOut)),
        )

        assertDecided(CoinageTransactionStatus.FAILURE, outcome)
    }

    @Test
    fun `Rule 3 does not fire before mortality has expired`() = runBlocking<Unit> {
        val entry = entry(outputs = listOf(coinOut))

        val outcome = evaluate(
            entry,
            evidence(finalizedNumber = MORTALITY_END, absentAtFinalized = setOf(coinOut), absentAtBest = setOf(coinOut)),
        )

        assertDecided(CoinageTransactionStatus.PENDING, outcome)
    }

    @Test
    fun `Rule 4 fails the entry when an input is still available after mortality`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(coinIn), outputs = listOf(coinOut))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = MORTALITY_END + 1,
                presentAtFinalized = setOf(coinIn),
                // Not absent, so Rule 3 cannot fire and Rule 4 is reached.
                unreadable = setOf(coinOut),
            ),
        )

        assertDecided(CoinageTransactionStatus.FAILURE, outcome)
    }

    @Test
    fun `Rule 4 does not fire before mortality has expired`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(coinIn), outputs = listOf(coinOut))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = MORTALITY_END,
                presentAtFinalized = setOf(coinIn),
                presentAtBest = setOf(coinIn),
                unreadable = setOf(coinOut),
            ),
        )

        assertDecided(CoinageTransactionStatus.PENDING, outcome)
    }

    // ---- Rules 5 and 6 — our own coins gone ----

    @Test
    fun `Rule 5 finalizes when every own-coin input is gone at the finalized head`() = runBlocking<Unit> {
        val minter = finalizedMinter(coinIn)
        val entry = entry(inputs = listOf(coinIn))

        val outcome = evaluate(
            entry,
            evidence(absentAtFinalized = setOf(coinIn), absentAtBest = setOf(coinIn)),
            dag(minter, entry),
        )

        assertDecided(CoinageTransactionStatus.FINALIZED_SUCCESS, outcome)
    }

    @Test
    fun `Rule 6 does not fire on an unexecuted entry - a registered unincluded split stays PENDING`() = runBlocking<Unit> {
        val minter = finalizedMinter(coinIn)
        val entry = entry(inputs = listOf(coinIn), outputs = listOf(coinOut))

        // The input is still there at both heads: the split never executed.
        val outcome = evaluate(
            entry,
            evidence(
                presentAtFinalized = setOf(coinIn),
                presentAtBest = setOf(coinIn),
                absentAtFinalized = setOf(coinOut),
                absentAtBest = setOf(coinOut),
            ),
            dag(minter, entry),
        )

        assertDecided(CoinageTransactionStatus.PENDING, outcome)
    }

    @Test
    fun `ownCoinInputs declines when an input has ever carried a handoff mark`() = runBlocking<Unit> {
        val minter = finalizedMinter(coinIn)
        val entry = entry(inputs = listOf(coinIn))

        val outcome = evaluate(
            entry,
            evidence(absentAtFinalized = setOf(coinIn), absentAtBest = setOf(coinIn)),
            dag(minter, entry, handedOff = setOf(coinIn.publicKey)),
        )

        // Falls through to the search rather than reading absence as consumption.
        assertDecided(CoinageTransactionStatus.PENDING, outcome)
        assertReachedSearch()
    }

    @Test
    fun `ownCoinInputs declines while the input minter's own window is still open`() = runBlocking<Unit> {
        val minter = finalizedMinter(coinIn, checkpointNumber = 200)
        val entry = entry(inputs = listOf(coinIn))

        val outcome = evaluate(
            entry,
            evidence(absentAtFinalized = setOf(coinIn), absentAtBest = setOf(coinIn)),
            dag(minter, entry),
        )

        assertDecided(CoinageTransactionStatus.PENDING, outcome)
        assertReachedSearch()
    }

    @Test
    fun `a failed read never satisfies absent, so Rule 5 cannot fire on it`() = runBlocking<Unit> {
        val minter = finalizedMinter(coinIn)
        val entry = entry(inputs = listOf(coinIn))

        val outcome = evaluate(
            entry,
            evidence(unreadable = setOf(coinIn)),
            dag(minter, entry),
        )

        assertDecided(CoinageTransactionStatus.PENDING, outcome)
        assertReachedSearch()
    }

    // ---- Rule 7 — body search ----

    @Test
    fun `Rule 7 finalizes on a successful dispatch in the searched block`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(receivedIn))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = MORTALITY_END + 1,
                unreadable = setOf(receivedIn),
            ),
            search = TransactionSearchResult.Found(block(120), ExtrinsicOutcome.SUCCESS),
        )

        assertDecided(CoinageTransactionStatus.FINALIZED_SUCCESS, outcome)
    }

    @Test
    fun `Rule 7 fails on a failed dispatch - inclusion is not success`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(receivedIn))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = MORTALITY_END + 1,
                unreadable = setOf(receivedIn),
            ),
            search = TransactionSearchResult.Found(block(120), ExtrinsicOutcome.FAILURE),
        )

        assertDecided(CoinageTransactionStatus.FAILURE, outcome)
    }

    @Test
    fun `Rule 7 leaves the entry PENDING when the outcome could not be read`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(receivedIn))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = MORTALITY_END + 1,
                unreadable = setOf(receivedIn),
            ),
            search = TransactionSearchResult.Found(block(120), outcome = null),
        )

        assertDecided(CoinageTransactionStatus.PENDING, outcome)
    }

    @Test
    fun `Rule 7 fails only once the whole window was read and mortality has expired`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(receivedIn))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = MORTALITY_END + 1,
                unreadable = setOf(receivedIn),
            ),
            search = TransactionSearchResult.NotFound(wholeRangeRead = true),
        )

        assertDecided(CoinageTransactionStatus.FAILURE, outcome)
    }

    @Test
    fun `a partially read window leaves the entry PENDING`() = runBlocking<Unit> {
        val entry = entry(inputs = listOf(receivedIn))

        val outcome = evaluate(
            entry,
            evidence(
                finalizedNumber = MORTALITY_END + 1,
                unreadable = setOf(receivedIn),
            ),
            search = TransactionSearchResult.NotFound(wholeRangeRead = false),
        )

        assertDecided(CoinageTransactionStatus.PENDING, outcome)
    }

    // ---- fixtures ----

    private val coinIn = coin(1)
    private val coinOut = coin(2)
    private val voucherIn = voucher(3)
    private val receivedIn = received(4)

    /** The ladder consults the view for one thing only: the body search of its last rule. */
    private val chainView: CoinageChainView = mock()

    private suspend fun evaluate(
        entry: LedgerEntry,
        evidence: ChainEvidence,
        dag: CoinageEntryDag = dag(entry),
        search: TransactionSearchResult = TransactionSearchResult.NotFound(wholeRangeRead = false),
    ): RuleOutcome {
        whenever(chainView.searchForTransaction(anyLong(), anyLong(), anyString())).thenReturn(search)
        return evaluateRules(entry, dag, evidence, chainView)
    }

    /** The ladder reached the last rule instead of deciding on state alone. */
    private suspend fun assertReachedSearch() {
        verify(chainView).searchForTransaction(anyLong(), anyLong(), anyString())
    }

    private fun assertDecided(
        expectedStatus: CoinageTransactionStatus,
        outcome: RuleOutcome,
    ): RuleOutcome.Decided {
        assertTrue("expected a decision but was $outcome", outcome is RuleOutcome.Decided)
        outcome as RuleOutcome.Decided
        assertEquals(expectedStatus, outcome.verdict.status)
        return outcome
    }

    private fun dag(
        vararg entries: LedgerEntry,
        handedOff: Set<DataByteArray> = emptySet(),
    ) = CoinageEntryDag(entries.toList(), handedOff)

    /** A finalized entry that minted [asset] long enough ago that its window has closed. */
    private fun finalizedMinter(asset: LedgerAsset, checkpointNumber: Long = 0) = entry(
        id = MINTER_ID,
        outputs = listOf(asset),
        status = CoinageTransactionStatus.FINALIZED_SUCCESS,
        checkpointNumber = checkpointNumber,
    )

    private fun entry(
        id: Long = ENTRY_ID,
        inputs: List<LedgerAsset> = emptyList(),
        outputs: List<LedgerAsset> = emptyList(),
        status: CoinageTransactionStatus = CoinageTransactionStatus.PENDING,
        successDetectedAt: CheckpointBlock? = null,
        checkpointNumber: Long = CHECKPOINT_NUMBER,
    ) = LedgerEntry(
        id = CoinageTransactionId(id),
        groupId = null,
        txHash = "0xtx$id",
        checkpoint = CheckpointBlock(checkpointNumber, "0xcheckpoint"),
        mortalityBlocks = MORTALITY,
        successDetectedAt = successDetectedAt,
        status = status,
        inputs = inputs,
        outputs = outputs,
    )
}

private const val ENTRY_ID = 2L
private const val MINTER_ID = 1L

private val BEST_BLOCK = CheckpointBlock(200, "0xbest")

private fun block(number: Long) = CheckpointBlock(number, "0xblock$number")

private fun key(tag: Int) = byteArrayOf(tag.toByte()).toDataByteArray()

private fun coin(tag: Int) = LedgerAsset(CoinageAssetKind.COIN, OwnAsset.Coin(tag), key(tag))

private fun voucher(tag: Int) = LedgerAsset(CoinageAssetKind.VOUCHER, OwnAsset.Voucher(tag), key(tag))

/** A coin whose key a peer sent us: no local identity, only an on-chain one. */
private fun received(tag: Int) = LedgerAsset(CoinageAssetKind.COIN, null, key(tag))

/**
 * Assets listed in [unreadable] appear in no map at all, which is how a failed read is expressed — every
 * lookup returns null and every predicate over it is false.
 */
private fun evidence(
    finalizedNumber: Long = 150,
    presentAtFinalized: Set<LedgerAsset> = emptySet(),
    absentAtFinalized: Set<LedgerAsset> = emptySet(),
    presentAtBest: Set<LedgerAsset> = emptySet(),
    absentAtBest: Set<LedgerAsset> = emptySet(),
    unloadedAtFinalized: Set<LedgerAsset> = emptySet(),
    unreadable: Set<LedgerAsset> = emptySet(),
    recordedBlockStillCanonical: Boolean? = null,
): ChainEvidence {
    fun presence(present: Set<LedgerAsset>, absent: Set<LedgerAsset>) =
        (present.map { it.publicKey to ChainPresence.PRESENT } + absent.map { it.publicKey to ChainPresence.ABSENT })
            .filterNot { (key, _) -> key in unreadable.map { it.publicKey } }
            .toMap()

    val aliases = unloadedAtFinalized.associate { it.publicKey to AliasRead.UNLOADED }

    return ChainEvidence(
        finalized = CheckpointBlock(finalizedNumber, "0xfinalized"),
        best = BEST_BLOCK,
        presenceAtFinalized = presence(presentAtFinalized, absentAtFinalized),
        presenceAtBest = presence(presentAtBest, absentAtBest),
        aliasAtFinalized = aliases,
        aliasAtBest = aliases,
        recordedBlockStillCanonical = recordedBlockStillCanonical,
    )
}
