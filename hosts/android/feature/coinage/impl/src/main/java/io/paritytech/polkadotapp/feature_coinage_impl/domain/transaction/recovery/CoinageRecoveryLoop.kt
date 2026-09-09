package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery

import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainViewFactory
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.transformWhile
import javax.inject.Inject
import javax.inject.Singleton

/** Why a pass is being run. Kept for the log — the pass itself reads the chain the same way whatever woke it. */
private enum class Trigger { LAUNCH, FINALIZED_HEAD, BEST_HEAD, MANUAL_TRIGGER }

/**
 * Runs recovery passes until the ledger holds no live entry.
 *
 * A pass is worth running exactly when the facts the rules read can have changed: a new best block moves
 * inclusion and payment status, a new finalized block moves everything terminal, and a released submission
 * hands an entry back that the pass had been skipping. All three feed one runner.
 *
 * The stream is conflated, so a pass takes as long as it takes and the heads that arrive meanwhile collapse
 * into a single follow-up rather than queueing into a backlog the loop can never work off.
 *
 * The loop holds no durable state — every pass re-derives everything from the ledger and the chain — so it
 * can be stopped at any point and resumed by being called again.
 */
@Singleton
class CoinageRecoveryLoop @Inject constructor(
    private val repository: CoinageEntryRepository,
    private val recoveryPass: CoinageRecoveryPass,
    private val chainViewFactory: CoinageChainViewFactory,
) {
    // Dropping oldest is right: a nudge says "something may be decidable now", and a newer one says it at
    // least as well. What must not happen is a nudge blocking the caller that raised it.
    private val nudges = MutableSharedFlow<Trigger>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    /**
     * Asks for a pass without waiting for a head. Recovery has to be running for this to be acted on — it
     * brings nothing up by itself.
     */
    fun manualTrigger() {
        nudges.tryEmit(Trigger.MANUAL_TRIGGER)
    }

    /**
     * Returns once nothing is live. Fails when a head subscription does, which the caller retries: a lost
     * subscription would otherwise leave live entries with nothing driving them.
     */
    suspend fun runUntilSettled(): Result<Unit> = runCancellableCatching {
        triggers()
            .conflate()
            .transformWhile { trigger ->
                runPass(trigger)
                emit(Unit)
                hasLiveEntries()
            }
            .collect()
    }

    /**
     * [onStart] rather than a pass before the subscription: a ledger that settled while the app was dead is
     * decided by the first pass and the loop ends without ever seeing a head.
     */
    private fun triggers() = merge(
        chainViewFactory.finalizedHeads().map { Trigger.FINALIZED_HEAD },
        chainViewFactory.bestHeads().map { Trigger.BEST_HEAD },
        nudges,
    ).onStart { emit(Trigger.LAUNCH) }

    private suspend fun runPass(trigger: Trigger) {
        coinageLogD("recovery-trigger $trigger")

        recoveryPass.run().onFailure { coinageLogW("recovery-pass-failed trigger=$trigger error=$it") }
    }

    /** An unreadable ledger counts as live: abandoning entries is far worse than one wasted pass. */
    private suspend fun hasLiveEntries(): Boolean = repository.hasLiveEntries()
        .onFailure { coinageLogW("live-entries-read-failed error=$it") }
        .getOrDefault(true)
}
