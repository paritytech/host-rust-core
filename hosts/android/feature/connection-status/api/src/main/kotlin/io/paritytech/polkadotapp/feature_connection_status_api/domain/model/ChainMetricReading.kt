package io.paritytech.polkadotapp.feature_connection_status_api.domain.model

import kotlin.time.Duration
import kotlin.time.Instant

/**
 * One metric's contribution for a chain: its [score] plus the raw domain value it was derived from.
 * The metric type and its value are one sealed field — adding a metric adds a variant here, a probe
 * that emits it, and a UI branch that formats it. Formatting stays in the presentation layer.
 */
sealed interface ChainMetricReading {
    val score: ChainHealthScore

    /**
     * Fewer than [requiredBlocks] of the [expectedBlocks] means the chain is not producing.
     * [lastBlockAt] is when the most recent one landed, so a consumer can age it on its own clock.
     * [expectedBlocks] stays derived from the chain's configured block time, so the outage line cannot
     * drift towards whatever rate the chain currently runs at.
     */
    data class BlockProduction(
        val recentBlocks: Int,
        val expectedBlocks: Int,
        val requiredBlocks: Int,
        val lastBlockAt: Instant?,
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
