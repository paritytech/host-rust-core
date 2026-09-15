package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe

import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.BlockLatencyWindow
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.ChainHealthThresholds
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.LivenessScorer
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.ExperimentalTime

/**
 * Latency of best-block production. The score is driven by the worse of the 10-block moving-average
 * interval and the raw time since the last block, re-evaluated on every new block and on a periodic
 * tick so the ring depletes during a stall even while no block arrives.
 */
@OptIn(ExperimentalTime::class)
class BlockLivenessProbe @Inject constructor(
    private val livenessScorer: LivenessScorer,
    private val timeProvider: TimeProvider,
) : ChainHealthProbe {
    override fun observe(context: ChainMetricContext): Flow<ChainMetricReading> = flow {
        val window = BlockLatencyWindow(ChainHealthThresholds.LATENCY_WINDOW_SIZE)
        val blockTimeMillis = context.expectedBlockTime.inWholeMilliseconds
        val target = context.expectedBlockTime * ChainHealthThresholds.LIVENESS_PLATEAU_MULTIPLIER
        val connectAnchor = now()

        val blocks = context.bestBlockNumber.distinctUntilChanged().map { Event.Block }
        val ticks = ticker(ChainHealthThresholds.LIVENESS_TICK)

        emitAll(
            merge(blocks, ticks).map {
                val now = now()
                if (it is Event.Block) window.recordArrival(now)

                val averageLatency = window.averageIntervalMillis()
                val elapsedSinceLastBlock = now - (window.lastArrivalMillis() ?: connectAnchor)
                val representativeLatency = maxOf(averageLatency ?: 0L, elapsedSinceLastBlock)

                ChainMetricReading.BlockLatency(
                    latency = representativeLatency.milliseconds,
                    target = target,
                    score = livenessScorer.score(blockTimeMillis, averageLatency, elapsedSinceLastBlock),
                )
            }.distinctUntilChanged()
        )
    }

    private fun now(): Long = timeProvider.now().toEpochMilliseconds()

    private fun ticker(period: Duration): Flow<Event> = flow {
        while (true) {
            emit(Event.Tick)
            delay(period)
        }
    }

    private sealed interface Event {
        data object Block : Event
        data object Tick : Event
    }
}
