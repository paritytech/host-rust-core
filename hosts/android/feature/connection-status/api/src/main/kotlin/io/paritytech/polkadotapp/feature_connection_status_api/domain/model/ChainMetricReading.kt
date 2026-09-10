package io.paritytech.polkadotapp.feature_connection_status_api.domain.model

import kotlin.time.Duration

/**
 * One metric's contribution for a chain: its [score] plus the raw domain value it was derived from.
 * The metric type and its value are one sealed field — adding a metric adds a variant here, a probe
 * that emits it, and a UI branch that formats it. Formatting stays in the presentation layer.
 */
sealed interface ChainMetricReading {
    val score: ChainHealthScore

    data class BlockLatency(
        val latency: Duration,
        val target: Duration,
        override val score: ChainHealthScore,
    ) : ChainMetricReading

    data class FinalityGap(
        val gapBlocks: Int,
        val targetBlocks: Int,
        override val score: ChainHealthScore,
    ) : ChainMetricReading

    /** How long the oldest still-pending socket request has been waiting. */
    data class PendingRequestLatency(
        val latency: Duration,
        val target: Duration,
        override val score: ChainHealthScore,
    ) : ChainMetricReading

    /** Average round-trip of recently-completed socket requests (a connection-throughput proxy). */
    data class ResponseLatency(
        val latency: Duration,
        val target: Duration,
        override val score: ChainHealthScore,
    ) : ChainMetricReading
}
