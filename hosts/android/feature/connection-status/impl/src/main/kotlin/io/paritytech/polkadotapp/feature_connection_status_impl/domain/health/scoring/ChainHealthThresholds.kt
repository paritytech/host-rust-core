package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring

import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * All tunable chain-health constants in one place. These are heuristic starting points chosen to
 * keep a healthy chain's metrics pinned at 100 and only degrade once a metric breaches its
 * tolerance — retune here after observing behaviour on live networks.
 */
object ChainHealthThresholds {
    // Re-evaluation cadence, so a score decays during a stall instead of holding its last value.
    val SAMPLE_TICK: Duration = 1.seconds

    val BLOCK_PRODUCTION_WINDOW: Duration = 30.seconds

    // The health rules call a chain that produced fewer than five sixths of its expected blocks an outage.
    const val BLOCK_PRODUCTION_REQUIRED_RATIO = 5.0 / 6.0

    val PENDING_REQUEST_IDEAL: Duration = 500.milliseconds

    val PENDING_REQUEST_OUTAGE: Duration = 5.seconds

    val RESPONSE_LATENCY_IDEAL: Duration = 300.milliseconds

    val RESPONSE_LATENCY_OUTAGE: Duration = 3.seconds

    val RESPONSE_LATENCY_WINDOW: Duration = 30.seconds
}
