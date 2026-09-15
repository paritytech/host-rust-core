package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.submission

import io.novasama.substrate_sdk_android.runtime.extrinsic.signer.SendableExtrinsic
import io.paritytech.polkadotapp.chains.extrinsic.ExtrinsicStatus
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.connection.ChainConnectionRefCounter
import io.paritytech.polkadotapp.chains.multiNetwork.connection.withConnectionEnabled
import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.ExtrinsicOutcome
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionStatus
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainViewFactory
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.Verdict
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogI
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.coinageLogId
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.shortHash
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.retry.PreSubmissionValidationFailed
import io.paritytech.polkadotapp.feature_transactions.api.data.retry.ResubmitWhenValidFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds

/**
 * Follows one extrinsic from submission. Its purpose is latency: it learns of inclusion and finality faster
 * than polling would.
 *
 * It proposes; it does not write. Every status change goes through the same compare-and-set the recovery
 * pass uses, so the guards apply uniformly.
 *
 * It owns the entries it watches, and ownership is one-shot: released exactly once, never taken back — not
 * on a resubmission, not on anything. Release drops the entry, stops the subscription and triggers a pass.
 */
class CoinageSubmissionTracker @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val extrinsicService: ExtrinsicService,
    private val repository: CoinageEntryRepository,
    private val chainViewFactory: CoinageChainViewFactory,
    private val submissionOwnedEntries: SubmissionOwnedEntries,
    private val resubmitWhenValidFactory: ResubmitWhenValidFactory,
    private val chainConnectionRefCounter: ChainConnectionRefCounter,
) {
    fun watch(
        scope: CoroutineScope,
        id: CoinageTransactionId,
        extrinsic: SendableExtrinsic,
        onReleased: () -> Unit,
    ) {
        scope.launch {
            runCatching { follow(id, extrinsic) }
                .onFailure { coinageLogW("${coinageLogId(id)} submission-watch-failed error=$it") }

            submissionOwnedEntries.release(id)

            // Recovery is for entries nobody has decided. A watch that ended by writing a terminal verdict
            // has already done the deciding, and a terminal entry is never rewritten — so asking for a pass
            // would schedule a worker and pin a chain view to re-derive an answer that exists. On the happy
            // path that is every transaction the app submits.
            //
            // Keyed on what the entry now says rather than on why the watch ended: a finalized block whose
            // outcome could not be read, or a proposal the compare-and-set refused, both leave it live and
            // genuinely needing the pass.
            if (needsRecovery(id)) onReleased()
        }
    }

    /** Unreadable counts as needing recovery: the pass re-reads it, where guessing here could strand it. */
    private suspend fun needsRecovery(id: CoinageTransactionId): Boolean {
        val status = repository.getStatus(id).getOrNull()

        if (status?.isLive == false) {
            coinageLogD("${coinageLogId(id)} recovery-skipped reason=decided status=$status")

            return false
        }

        return true
    }

    private suspend fun follow(id: CoinageTransactionId, extrinsic: SendableExtrinsic) {
        val chain = chainAssetProvider.chain()

        // Held for as long as the watch lives. This subscription is the only thing following the transaction
        // while it is in flight, and a connection torn down because the app went to background would end it —
        // handing the entry to the recovery pass to decide the slow way, over its whole mortality window.
        chainConnectionRefCounter.withConnectionEnabled(chain.id, CONNECTION_LABEL) {
            watchSubmission(id, chain, extrinsic)
        }
    }

    private suspend fun watchSubmission(
        id: CoinageTransactionId,
        chain: Chain,
        extrinsic: SendableExtrinsic,
    ) = coroutineScope {
        // Only a post-pool invalidation is worth resubmitting: anything else releases the entry to the
        // recovery pass, which is the one place allowed to decide it.
        val recoveryStrategy = resubmitWhenValidFactory.createForTxInvalidation(chain.id, RECOVERY_MAX_ATTEMPTS)
        val events = Channel<ExtrinsicStatus>(Channel.BUFFERED)

        val pump = launch {
            runCatching {
                extrinsicService.submitAndWatchBuiltExtrinsic(chain, extrinsic, recoveryStrategy)
                    .collect(events::send)
            }
            events.close()
        }

        try {
            while (true) {
                // Thirty seconds is about fifteen blocks against a 128-block mortality, so the timeout always
                // fires long before the extrinsic can no longer execute. A dead subscription is handled as
                // the watcher releasing rather than as someone else invalidating it.
                val status = withTimeoutOrNull(SILENCE_TIMEOUT) {
                    events.receiveCatching().getOrNull()
                }

                if (status == null) {
                    coinageLogW("${coinageLogId(id)} submission-abandoned reason=silence-timeout")
                    break
                }

                // Only the status that ends the watch goes to info: a batch of twenty vouchers reports four
                // times each, which would spend the whole breadcrumb budget on one operation.
                val line = "${coinageLogId(id)} submission-status ${status.describe()}"
                if (status.terminal) coinageLogI(line) else coinageLogD(line)

                if (handle(id, status)) break
            }
        } finally {
            pump.cancel()
        }
    }

    /** Returns true when the entry is done being watched. */
    private suspend fun handle(
        id: CoinageTransactionId,
        status: ExtrinsicStatus,
    ): Boolean = when (status) {
        // Pre-inclusion states carry no evidence either way. They must not lower an entry that has some: the
        // resubmission path keeps consuming this flow after an inclusion, so one of these can arrive behind an
        // InBlock, and clearing the record there would withdraw the outputs' selectability on nothing. Only a
        // retraction says a recorded block is gone.
        is ExtrinsicStatus.Future,
        is ExtrinsicStatus.Ready,
        is ExtrinsicStatus.Broadcast -> false

        // Not finalized, so a terminal verdict must not rest on it: a proven failure here proposes nothing
        // and the entry stays PENDING for the pass to decide.
        is ExtrinsicStatus.InBlock -> {
            val at = blockOf(status.blockHash)
            val outcome = at?.let { dispatchOutcome(status.blockHash, id) }

            coinageLogD("${coinageLogId(id)} in-block block=${at?.blockNumber} outcome=$outcome")

            if (outcome == ExtrinsicOutcome.SUCCESS) {
                propose(id, Verdict(CoinageTransactionStatus.PENDING_SUCCESS, successDetectedAt = at))
            }
            false
        }

        is ExtrinsicStatus.Retracted -> {
            clearRecordIfItNames(id, status.blockHash)
            false
        }

        is ExtrinsicStatus.Finalized -> {
            val outcome = dispatchOutcome(status.blockHash, id)

            coinageLogD("${coinageLogId(id)} finalized outcome=$outcome")

            when (outcome) {
                ExtrinsicOutcome.SUCCESS ->
                    propose(id, Verdict(CoinageTransactionStatus.FINALIZED_SUCCESS, blockOf(status.blockHash)))

                ExtrinsicOutcome.FAILURE ->
                    propose(id, Verdict(CoinageTransactionStatus.FAILURE, successDetectedAt = null))

                null -> Unit
            }
            true
        }

        // Recovery has already had its chance to resubmit by the time these surface as terminal.
        is ExtrinsicStatus.Dropped,
        is ExtrinsicStatus.Invalid,
        is ExtrinsicStatus.Usurped -> true

        is ExtrinsicStatus.FailedToSubmit -> {
            // Validation runs before the extrinsic is handed to a node and a rejection there is only ever
            // propagated when recovery declined to resubmit, so nothing can ever include these bytes:
            // finalized-grade evidence without waiting for finality. The recovery contract is what keeps
            // that true — a strategy is given no way to submit anything itself.
            if (status.exception is PreSubmissionValidationFailed) {
                propose(id, Verdict(CoinageTransactionStatus.FAILURE, successDetectedAt = null))
            }
            true
        }

        is ExtrinsicStatus.Other -> false
    }

    /**
     * The record is cleared only when it names the block that was retracted; the status is lowered with it,
     * because leaving PENDING_SUCCESS behind with no evidence would keep the outputs spendable for a whole
     * mortality window on the strength of a block that no longer exists.
     */
    private suspend fun clearRecordIfItNames(id: CoinageTransactionId, blockHash: String) {
        val entry = repository.getEntry(id).getOrNull() ?: return
        if (entry.successDetectedAt?.blockHash != blockHash) return

        propose(id, Verdict(CoinageTransactionStatus.PENDING, successDetectedAt = null))
    }

    /**
     * A terminal entry is never rewritten, so a late event cannot un-fail a failed transaction; the
     * compare-and-set then covers a status that moved since it was read.
     */
    private suspend fun propose(id: CoinageTransactionId, verdict: Verdict) {
        val observed = repository.getStatus(id).getOrNull() ?: run {
            coinageLogW("${coinageLogId(id)} proposal-skipped to=${verdict.status} reason=status-unreadable")

            return
        }

        if (!observed.isLive) {
            coinageLogD("${coinageLogId(id)} proposal-skipped to=${verdict.status} reason=not-live observed=$observed")

            return
        }

        coinageLogD(
            "${coinageLogId(id)} proposing from=$observed to=${verdict.status} " +
                "record=${verdict.successDetectedAt?.blockNumber ?: "none"}"
        )

        repository.compareAndSetStatus(id, observed, verdict)
            .onFailure { coinageLogW("${coinageLogId(id)} proposal-write-failed to=${verdict.status} error=$it") }
    }

    private suspend fun dispatchOutcome(blockHash: String, id: CoinageTransactionId): ExtrinsicOutcome? {
        val entry = repository.getEntry(id).getOrNull() ?: return null
        val view = chainViewFactory.pin().getOrNull() ?: return null

        return view.dispatchOutcomeAt(blockHash, entry.txHash).getOrNull()
    }

    private suspend fun blockOf(blockHash: String): CheckpointBlock? {
        val view = chainViewFactory.pin().getOrNull() ?: return null
        val number = view.blockNumberAt(blockHash).getOrNull() ?: return null

        return CheckpointBlock(number, blockHash)
    }

    private companion object {
        const val CONNECTION_LABEL = "CoinageSubmission"

        val SILENCE_TIMEOUT = 30.seconds

        /** Mirrors the platform default; the constant itself lives in an impl module this cannot depend on. */
        const val RECOVERY_MAX_ATTEMPTS = 3
    }
}

private fun ExtrinsicStatus.describe(): String = when (this) {
    is ExtrinsicStatus.InBlock -> "InBlock at=${blockHash.shortHash()}"
    is ExtrinsicStatus.Retracted -> "Retracted at=${blockHash.shortHash()}"
    is ExtrinsicStatus.Finalized -> "Finalized at=${blockHash.shortHash()}"
    is ExtrinsicStatus.FailedToSubmit -> "FailedToSubmit error=${exception::class.simpleName}"
    is ExtrinsicStatus.Usurped -> "Usurped by=${this.by.shortHash()}"
    is ExtrinsicStatus.Other -> "Other raw=$rawStatus"
    else -> this::class.simpleName.orEmpty()
}
