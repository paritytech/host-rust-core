package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery

/**
 * Brings the recovery loop up, wherever it is hosted.
 *
 * A seam rather than a direct `WorkManager` call so that the transaction service — which decides *when*
 * recovery is needed — never has to hold an Android context.
 */
interface CoinageRecoveryScheduler {
    /** Idempotent: a no-op while a loop is already running. */
    fun ensureRunning()
}
