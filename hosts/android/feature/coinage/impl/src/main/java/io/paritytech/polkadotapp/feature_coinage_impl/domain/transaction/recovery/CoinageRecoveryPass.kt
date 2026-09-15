package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery

import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainView
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainViewFactory
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.LedgerEntry
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.Verdict
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogI
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.logId
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.submission.SubmissionOwnedEntries
import kotlinx.coroutines.sync.Mutex
import javax.inject.Inject
import javax.inject.Singleton

/** One evaluation of every live entry that submission tracking does not own. */
interface CoinageRecoveryPass {
    /** At most one pass runs at a time; a call made while one is running is a no-op. */
    suspend fun run(): Result<Unit>
}

/**
 * Rules run entirely outside the database transaction — the body search can span a whole mortality window,
 * which must never hold a write open. The write is then a compare-and-set against the status the rules were
 * evaluated from, so a status that moved underneath costs that entry a pass and nothing else.
 */
@Singleton
class RealCoinageRecoveryPass @Inject constructor(
    private val repository: CoinageEntryRepository,
    private val chainViewFactory: CoinageChainViewFactory,
    private val evidenceCollector: CoinageEvidenceCollector,
    private val submissionOwnedEntries: SubmissionOwnedEntries,
) : CoinageRecoveryPass {
    // One pass at a time. In memory, so a crash takes it with it and the next launch is free to start.
    private val running = Mutex()

    override suspend fun run(): Result<Unit> {
        if (!running.tryLock()) {
            coinageLogD("recovery-pass skipped reason=already-running")

            return Result.success(Unit)
        }

        return try {
            runPass()
        } finally {
            running.unlock()
        }
    }

    /**
     * A pass-level read failing means there is no pinned view or no ledger to evaluate against, so the pass
     * aborts and the next one repeats it; nothing is written and nothing is lost.
     */
    private suspend fun runPass(): Result<Unit> {
        val dag = loadDag().getOrElse { return Result.failure(it) }

        val decidable = dag.entries.filter { it.status.isLive && !submissionOwnedEntries.isOwnedBySubmission(it.id) }

        // Nothing to decide means nothing to propagate either — propagation walks the same set — so the pass
        // ends here rather than pinning a view, which is a chain read with nothing to read it for. Passes are
        // triggered per head, so a settled ledger would otherwise pay for one on every block.
        if (decidable.isEmpty()) {
            coinageLogD("recovery-pass skipped reason=nothing-decidable entries=${dag.entries.size}")

            return Result.success(Unit)
        }

        val view = chainViewFactory.pin().getOrElse { return Result.failure(it) }

        coinageLogD(
            "recovery-pass start entries=${dag.entries.size} decidable=${decidable.size} " +
                "f=${view.finalizedHead.blockNumber} b=${view.bestHead.blockNumber}"
        )

        val written = decidable.count { decide(it, dag, view) }
        val anyWritten = written > 0

        // Propagation reads statuses, so it needs the ones this pass just wrote: an entry promoted above is
        // exactly the successor that lets its predecessor be promoted too.
        val propagationDag = if (anyWritten) loadDag().getOrElse { return Result.failure(it) } else dag

        val propagated = propagate(propagationDag)

        coinageLogD(
            "recovery-pass end entries=${dag.entries.size} decidable=${decidable.size} " +
                "written=$written propagated=$propagated"
        )

        return Result.success(Unit)
    }

    private suspend fun loadDag(): Result<CoinageEntryDag> {
        val entries = repository.getAllEntries().getOrElse { return Result.failure(it) }
        val handedOffKeys = repository.getHandoffKeys().getOrElse { return Result.failure(it) }

        return Result.success(CoinageEntryDag(entries, handedOffKeys))
    }

    /** Returns whether it wrote. */
    private suspend fun decide(entry: LedgerEntry, dag: CoinageEntryDag, view: CoinageChainView): Boolean {
        val evidence = evidenceCollector.collect(entry, view)

        return when (val outcome = evaluateRules(entry, dag, evidence, view)) {
            // A failed read aborts this entry for this pass: it keeps its status and its locks, and is
            // retried. There is deliberately no status for "we don't know".
            RuleOutcome.Undecided -> false

            is RuleOutcome.Decided -> write(entry, entry.status, outcome.verdict)
        }
    }

    /**
     * A successor that consumed our output proves the output existed, and an output exists only if the entry
     * minting it executed. That is positive evidence, and it arrives before the entry's own window closes.
     *
     * The opposite direction needs no rule: a failed entry's outputs never existed, so its successors are
     * decided by their own mortality, in parallel, within one window rather than one window per hop.
     */
    private suspend fun propagate(dag: CoinageEntryDag): Int {
        return dag.entries
            .filter { it.status.isLive && !submissionOwnedEntries.isOwnedBySubmission(it.id) }
            .mapNotNull { entry ->
                val successor = dag.successors(entry)
                    .firstOrNull { it.status == CoinageTransactionStatus.FINALIZED_SUCCESS }
                    ?: return@mapNotNull null

                entry to successor
            }
            .count { (entry, successor) ->
                coinageLogI("${entry.logId()} propagate from=${entry.status} successor=${successor.id.value}")

                write(entry, entry.status, Verdict(CoinageTransactionStatus.FINALIZED_SUCCESS, entry.successDetectedAt))
            }
    }

    private suspend fun write(entry: LedgerEntry, observed: CoinageTransactionStatus, verdict: Verdict): Boolean {
        if (verdict.status == observed && verdict.successDetectedAt == entry.successDetectedAt) return false

        return repository.compareAndSetStatus(entry.id, observed, verdict)
            .onFailure { coinageLogW("${entry.logId()} verdict-write-failed to=${verdict.status} error=$it") }
            .getOrDefault(false)
    }
}
