package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery

import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.ExtrinsicOutcome
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainView
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerAsset
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerEntry
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.TransactionSearchResult
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.Verdict
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.logId

sealed interface RuleOutcome {
    data class Decided(val verdict: Verdict) : RuleOutcome

    /** A read this entry depended on failed. It keeps its status and its locks, and is retried. */
    data object Undecided : RuleOutcome
}

// ---- predicates over a pinned view -------------------------------------------------------------------
//
// Every one is positive-form and paired with its opposite. A read is three-valued, so `!exists` would mean
// "absent or unreadable" and a network error would start deciding things.

fun ChainEvidence.exists(asset: LedgerAsset, atFinalized: Boolean): Boolean =
    presence(atFinalized)[asset.publicKey] == ChainPresence.PRESENT

fun ChainEvidence.absent(asset: LedgerAsset, atFinalized: Boolean): Boolean =
    presence(atFinalized)[asset.publicKey] == ChainPresence.ABSENT

/** Always false for a coin: `CoinsByOwner` being empty is necessary but not sufficient for a coin to be spent. */
fun ChainEvidence.provenConsumedOnChain(asset: LedgerAsset, atFinalized: Boolean = true): Boolean =
    asset.isVoucher && alias(atFinalized)[asset.publicKey] == AliasRead.UNLOADED

fun ChainEvidence.provenNotUnloaded(asset: LedgerAsset, atFinalized: Boolean): Boolean =
    asset.isVoucher && alias(atFinalized)[asset.publicKey] == AliasRead.NOT_UNLOADED

/** The asset is still there to be spent. */
fun ChainEvidence.available(asset: LedgerAsset, atFinalized: Boolean): Boolean = when {
    asset.isCoin -> exists(asset, atFinalized)
    else -> exists(asset, atFinalized) && provenNotUnloaded(asset, atFinalized)
}

/** This entry can no longer execute, so anything it did has already happened below the finalized head. */
fun ChainEvidence.windowClosed(entry: LedgerEntry): Boolean = finalized.blockNumber > entry.mortalityEnd

fun ChainEvidence.executed(entry: LedgerEntry, atFinalized: Boolean): Boolean =
    entry.outputs.any { exists(it, atFinalized) } ||
        entry.inputs.any { provenConsumedOnChain(it, atFinalized) }

private fun ChainEvidence.presence(atFinalized: Boolean) =
    if (atFinalized) presenceAtFinalized else presenceAtBest

private fun ChainEvidence.alias(atFinalized: Boolean) =
    if (atFinalized) aliasAtFinalized else aliasAtBest

// ---- asset facts drawn from the graph and the view ----------------------------------------------------

/**
 * Once established this is permanent: a terminal status never changes, and a coin absent at a finalized head
 * can never come back, because addresses are never reused.
 */
private fun LedgerAsset.spent(dag: CoinageEntryDag, evidence: ChainEvidence): Boolean {
    // An entry that succeeded consumed all of its inputs.
    val consumedByFinalized = dag.consumers(publicKey)
        .any { it.status == CoinageTransactionStatus.FINALIZED_SUCCESS }

    return consumedByFinalized || evidence.provenConsumedOnChain(this) || spentByAbsence(dag, evidence)
}

/**
 * Absence read as consumption, with two guards: [isCoin], because a voucher's disappearance may be ring
 * cleaning; and the minter's window having closed, because a coin minted above a shallow finalized head
 * reads absent for the ordinary reason that it does not exist there yet.
 */
private fun LedgerAsset.spentByAbsence(dag: CoinageEntryDag, evidence: ChainEvidence): Boolean {
    if (!isCoin) return false
    val minter = dag.minter(publicKey) ?: return false

    return minter.status == CoinageTransactionStatus.FINALIZED_SUCCESS &&
        evidence.absent(this, atFinalized = true) &&
        evidence.windowClosed(minter)
}

/** Nothing could have removed this output, so its absence is meaningful. */
private fun LedgerAsset.noPotentialConsumers(dag: CoinageEntryDag, evidence: ChainEvidence): Boolean {
    if (dag.isHandedOff(publicKey)) return false
    if (spent(dag, evidence)) return false

    return dag.consumers(publicKey).none { it.status != CoinageTransactionStatus.FAILURE }
}

/**
 * Every input is a coin we minted ourselves, proven to have existed and old enough that its absence now is
 * meaningful. This is what resolves the ambiguity in Rules 5 and 6: a coin also reads absent before it was
 * ever minted.
 */
private fun LedgerEntry.hasOnlyProvenOwnCoinInputs(dag: CoinageEntryDag, evidence: ChainEvidence): Boolean {
    if (inputs.isEmpty()) return false

    return inputs.all { input ->
        val minter = dag.minter(input.publicKey)

        input.isCoin &&
            input.asset != null &&
            !dag.isHandedOff(input.publicKey) &&
            minter != null &&
            minter.status == CoinageTransactionStatus.FINALIZED_SUCCESS &&
            evidence.windowClosed(minter)
    }
}

// ---- the ladder --------------------------------------------------------------------------------------

/**
 * Decides one entry against one pinned view. Evaluated in order; the first rule that matches wins.
 *
 * [view] is consulted only by the last rule, which searches block bodies for the transaction itself.
 */
suspend fun evaluateRules(
    entry: LedgerEntry,
    dag: CoinageEntryDag,
    evidence: ChainEvidence,
    view: CoinageChainView,
): RuleOutcome {
    recordedInclusion(entry, evidence)?.let { return it }

    // Execution is visible at the finalized head.
    if (evidence.executed(entry, atFinalized = true)) {
        return evidence.decided(entry, "Rule 1 executed at F", CoinageTransactionStatus.FINALIZED_SUCCESS, entry.successDetectedAt)
    }

    // Execution is visible at the best head. The rule above is evaluated first and wins on the same
    // evidence, so the overlap only ever costs a weaker verdict.
    if (evidence.executed(entry, atFinalized = false)) {
        return evidence.decided(entry, "Rule 2 executed at B", CoinageTransactionStatus.PENDING_SUCCESS, evidence.best)
    }

    val windowClosed = evidence.windowClosed(entry)

    // An output that nothing could have removed is definitely not there, and the entry can no longer execute.
    if (windowClosed &&
        entry.outputs.any { it.noPotentialConsumers(dag, evidence) && evidence.absent(it, atFinalized = true) }
    ) {
        return evidence.decided(entry, "Rule 3 output absent", CoinageTransactionStatus.FAILURE, successDetectedAt = null)
    }

    // An input is definitely still there to be spent, and the entry can no longer execute.
    if (windowClosed && entry.inputs.any { evidence.available(it, atFinalized = true) }) {
        return evidence.decided(entry, "Rule 4 input available", CoinageTransactionStatus.FAILURE, successDetectedAt = null)
    }

    val provenOwnCoins = entry.hasOnlyProvenOwnCoinInputs(dag, evidence)

    // Every input is a proven-minted coin of ours and all of them are gone at the finalized head.
    if (provenOwnCoins && entry.inputs.all { evidence.absent(it, atFinalized = true) }) {
        return evidence.decided(entry, "Rule 5 own coins gone", CoinageTransactionStatus.FINALIZED_SUCCESS, entry.successDetectedAt)
    }

    // The same, except one input is still there at the finalized head, so they were consumed in the best
    // chain and it is not yet final.
    if (provenOwnCoins &&
        entry.inputs.any { evidence.exists(it, atFinalized = true) } &&
        entry.inputs.all { evidence.absent(it, atFinalized = false) }
    ) {
        return evidence.decided(entry, "Rule 6 own coins gone at B", CoinageTransactionStatus.PENDING_SUCCESS, evidence.best)
    }

    // Short circuits, so an entry with no positive evidence does not run a body search on every new head.
    // They must not fire once mortality has expired: past it the entry has to reach the search, which is the
    // only thing left that can decide it.
    if (!windowClosed &&
        entry.outputs.any { it.noPotentialConsumers(dag, evidence) && evidence.absent(it, atFinalized = false) }
    ) {
        return evidence.decided(entry, "Rule 3b output not yet there", CoinageTransactionStatus.PENDING, successDetectedAt = null)
    }

    if (!windowClosed && entry.inputs.any { evidence.available(it, atFinalized = false) }) {
        return evidence.decided(entry, "Rule 4b input still there", CoinageTransactionStatus.PENDING, successDetectedAt = null)
    }

    return searchForTransaction(entry, evidence, view, windowClosed)
}

/** Nothing above could decide it, so look for the transaction itself. */
private suspend fun searchForTransaction(
    entry: LedgerEntry,
    evidence: ChainEvidence,
    view: CoinageChainView,
    windowClosed: Boolean,
): RuleOutcome {
    val search = view.searchForTransaction(
        fromBlockNumber = entry.checkpoint.blockNumber,
        toBlockNumber = minOf(entry.mortalityEnd, evidence.finalized.blockNumber),
        txHash = entry.txHash,
    )

    return when (search) {
        is TransactionSearchResult.Found -> when (search.outcome) {
            ExtrinsicOutcome.SUCCESS -> evidence.decided(entry, "Rule 7 found, dispatch succeeded", CoinageTransactionStatus.FINALIZED_SUCCESS, search.block)

            // Inclusion is not success — an extrinsic can be applied and its dispatch still fail.
            ExtrinsicOutcome.FAILURE -> evidence.decided(entry, "Rule 7 found, dispatch failed", CoinageTransactionStatus.FAILURE, successDetectedAt = null)

            null -> evidence.decided(entry, "Rule 7 found, outcome unreadable", CoinageTransactionStatus.PENDING, successDetectedAt = null)
        }

        is TransactionSearchResult.NotFound ->
            if (search.wholeRangeRead && windowClosed) {
                evidence.decided(entry, "Rule 7 whole window read, absent", CoinageTransactionStatus.FAILURE, successDetectedAt = null)
            } else {
                evidence.decided(entry, "Rule 7 window incomplete", CoinageTransactionStatus.PENDING, successDetectedAt = null)
            }
    }
}

/**
 * We already saw this entry included somewhere; check that block is still real.
 *
 * The record is only ever written where success is already proven, so this never re-asks whether the
 * extrinsic took effect. It covers the entry whose output a peer claims before it finalizes: the output is
 * then gone, its own inputs are consumed, and the search cannot reach its block yet, so without the record
 * the entry would fall back to PENDING and its other outputs would lose optimistic selectability for a full
 * mortality window.
 */
private fun recordedInclusion(entry: LedgerEntry, evidence: ChainEvidence): RuleOutcome? {
    val recorded = entry.successDetectedAt ?: return null
    val stillCanonical = evidence.recordedBlockStillCanonical

    if (stillCanonical == null) {
        coinageLogW("${entry.logId()} rule=undecided reason=record-canonicality-unread record=${recorded.blockNumber}")

        return RuleOutcome.Undecided
    }

    if (!stillCanonical) {
        return when {
            // Asked before the best head, or a chain that reorgs its head between passes would keep
            // re-recording this entry above the finalized head and never let it finalize at all.
            evidence.executed(entry, atFinalized = true) ->
                evidence.decided(entry, "Rule 0 record gone, executed at F", CoinageTransactionStatus.FINALIZED_SUCCESS, evidence.finalized)

            evidence.executed(entry, atFinalized = false) ->
                evidence.decided(entry, "Rule 0 record gone, still at B", CoinageTransactionStatus.PENDING_SUCCESS, evidence.best)

            // Writes PENDING rather than only clearing the record: clearing alone would leave the entry
            // PENDING_SUCCESS with no evidence behind it, and its outputs spendable for a full mortality
            // window on the strength of a block that no longer exists.
            else -> evidence.decided(entry, "Rule 0 record gone, demoted", CoinageTransactionStatus.PENDING, successDetectedAt = null)
        }
    }

    return if (recorded.blockNumber <= evidence.finalized.blockNumber) {
        evidence.decided(entry, "Rule 0 record canonical at F", CoinageTransactionStatus.FINALIZED_SUCCESS, recorded)
    } else {
        evidence.decided(entry, "Rule 0 record canonical above F", CoinageTransactionStatus.PENDING_SUCCESS, recorded)
    }
}

/** Every terminal path names itself, so a log line says which rule spoke and not merely what it concluded. */
private fun ChainEvidence.decided(
    entry: LedgerEntry,
    rule: String,
    status: CoinageTransactionStatus,
    successDetectedAt: CheckpointBlock?,
): RuleOutcome {
    coinageLogD(
        "${entry.logId()} rule=\"$rule\" -> $status f=${finalized.blockNumber} b=${best.blockNumber} " +
            "record=${successDetectedAt?.blockNumber ?: "none"}"
    )

    return RuleOutcome.Decided(Verdict(status, successDetectedAt))
}
