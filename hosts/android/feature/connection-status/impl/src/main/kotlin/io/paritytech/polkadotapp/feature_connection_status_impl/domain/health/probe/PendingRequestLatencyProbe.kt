package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe

import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.PendingRequestTracker
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.ChainHealthThresholds
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.LatencyScorer
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.ExperimentalTime

/**
 * Latency of the oldest still-pending socket request. Requests carry no timestamp, so a
 * [PendingRequestTracker] records when each was first seen (by referential identity) and reports the
 * age of the oldest one. A ticker re-evaluates the age while the pending set is unchanged.
 */
@OptIn(ExperimentalTime::class)
class PendingRequestLatencyProbe @Inject constructor(
    private val scorer: LatencyScorer,
    private val timeProvider: TimeProvider,
) : ChainHealthProbe {
    override fun observe(context: ChainMetricContext): Flow<ChainMetricReading> {
        val tracker = PendingRequestTracker()
        val idealMillis = ChainHealthThresholds.PENDING_REQUEST_IDEAL.inWholeMilliseconds
        val outageMillis = ChainHealthThresholds.PENDING_REQUEST_OUTAGE.inWholeMilliseconds

        return combine(context.pendingRequests, ticker(ChainHealthThresholds.LIVENESS_TICK)) { pending, _ ->
            val oldestMillis = tracker.update(pending, now())

            ChainMetricReading.PendingRequestLatency(
                latency = oldestMillis.milliseconds,
                target = ChainHealthThresholds.PENDING_REQUEST_IDEAL,
                score = scorer.score(oldestMillis, idealMillis, outageMillis),
            )
        }.distinctUntilChanged()
    }

    private fun now(): Long = timeProvider.now().toEpochMilliseconds()

    private fun ticker(period: Duration): Flow<Unit> = flow {
        while (true) {
            emit(Unit)
            delay(period)
        }
    }
}
