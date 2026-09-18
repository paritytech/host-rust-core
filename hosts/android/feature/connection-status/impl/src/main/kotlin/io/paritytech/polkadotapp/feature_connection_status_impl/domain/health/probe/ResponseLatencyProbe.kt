package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe

import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.RequestResponseTracker
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.ChainHealthThresholds
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.LatencyScorer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChangedBy
import javax.inject.Inject
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.ExperimentalTime

/**
 * Estimates connection throughput as the average round-trip of recently-completed requests, derived
 * from pending-set churn (a request that leaves the pending set has completed). Reuses the same
 * pending-requests stream as [PendingRequestLatencyProbe]. Optimistic (full score) until at least one
 * request completes within the window.
 */
@OptIn(ExperimentalTime::class)
class ResponseLatencyProbe @Inject constructor(
    private val scorer: LatencyScorer,
    private val timeProvider: TimeProvider,
) : ChainHealthProbe {
    override fun observe(context: ChainMetricContext): Flow<ChainMetricReading> {
        val tracker = RequestResponseTracker(ChainHealthThresholds.RESPONSE_LATENCY_WINDOW.inWholeMilliseconds)
        val idealMillis = ChainHealthThresholds.RESPONSE_LATENCY_IDEAL.inWholeMilliseconds
        val outageMillis = ChainHealthThresholds.RESPONSE_LATENCY_OUTAGE.inWholeMilliseconds

        return combine(context.pendingRequests, context.ticks) { pending, _ ->
            val averageMillis = tracker.update(pending, now())

            ChainMetricReading.ResponseLatency(
                latency = (averageMillis ?: 0L).milliseconds,
                target = ChainHealthThresholds.RESPONSE_LATENCY_IDEAL,
                score = averageMillis
                    ?.let { scorer.score(it, idealMillis, outageMillis) }
                    ?: ChainHealthScore.Perfect,
            )
        }.distinctUntilChangedBy { it.score }
    }

    private fun now(): Long = timeProvider.now().toEpochMilliseconds()
}
