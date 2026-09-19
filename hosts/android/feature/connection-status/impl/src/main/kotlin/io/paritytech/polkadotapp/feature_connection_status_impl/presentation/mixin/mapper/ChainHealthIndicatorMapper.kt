package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin.mapper

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealth
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator.Speed

// Bands for the worst of the pending-request and response scores.
private const val CONNECTION_HIGH_FROM = 90
private const val CONNECTION_GOOD_FROM = 70
private const val CONNECTION_FAIR_FROM = 40

// Each band owns one quarter of the ring, so the arc keeps travelling inside a band instead of snapping
// between three fixed lengths: Low fills 0..90, Fair 90..180 and Good 180..270 degrees.
private const val BAND_ARC = 0.25f
private const val GOOD_ARC_FROM = 0.5f
private const val FAIR_ARC_FROM = 0.25f
private const val LOW_ARC_FROM = 0f

// A score at the very bottom of its band still has to draw something, or an empty ring reads as dead.
private const val MIN_ARC = 0.01f

internal fun ChainHealth.toIndicator(): ChainHealthIndicator = when (connection) {
    ChainConnectionPresentation.Disconnected -> ChainHealthIndicator.Disconnected
    ChainConnectionPresentation.Connecting -> ChainHealthIndicator.Connecting
    ChainConnectionPresentation.Connected -> when {
        nodeUnresponsive() -> ChainHealthIndicator.Disconnected
        notProducingBlocks() -> ChainHealthIndicator.Outage
        else -> connectionSpeed() ?: ChainHealthIndicator.Healthy
    }
}

private fun ChainHealth.nodeUnresponsive(): Boolean = readings
    .filterIsInstance<ChainMetricReading.PendingRequestLatency>()
    .any { it.score == ChainHealthScore.Zero }

private fun ChainHealth.notProducingBlocks(): Boolean = readings
    .filterIsInstance<ChainMetricReading.BlockProduction>()
    .any { it.recentBlocks < it.requiredBlocks }

private fun ChainHealth.connectionSpeed(): ChainHealthIndicator.ConnectionSpeed? {
    val worstScore = readings.filter { it.isConnectionSpeed() }.minOfOrNull { it.score.value } ?: return null

    return when {
        worstScore >= CONNECTION_HIGH_FROM -> null

        worstScore >= CONNECTION_GOOD_FROM -> speedIndicator(
            speed = Speed.Good,
            score = worstScore,
            scoreFrom = CONNECTION_GOOD_FROM,
            scoreTo = CONNECTION_HIGH_FROM - 1,
            arcFrom = GOOD_ARC_FROM,
        )

        worstScore >= CONNECTION_FAIR_FROM -> speedIndicator(
            speed = Speed.Fair,
            score = worstScore,
            scoreFrom = CONNECTION_FAIR_FROM,
            scoreTo = CONNECTION_GOOD_FROM - 1,
            arcFrom = FAIR_ARC_FROM,
        )

        else -> speedIndicator(
            speed = Speed.Low,
            score = worstScore,
            scoreFrom = ChainHealthScore.MIN_VALUE,
            scoreTo = CONNECTION_FAIR_FROM - 1,
            arcFrom = LOW_ARC_FROM,
        )
    }
}

private fun speedIndicator(
    speed: Speed,
    score: Int,
    scoreFrom: Int,
    scoreTo: Int,
    arcFrom: Float,
): ChainHealthIndicator.ConnectionSpeed {
    val progress = (score - scoreFrom).toFloat() / (scoreTo - scoreFrom)
    val arc = (arcFrom + progress * BAND_ARC).coerceIn(MIN_ARC, arcFrom + BAND_ARC)

    return ChainHealthIndicator.ConnectionSpeed(speed = speed, arc = arc)
}

private fun ChainMetricReading.isConnectionSpeed(): Boolean = when (this) {
    is ChainMetricReading.PendingRequestLatency, is ChainMetricReading.ResponseLatency -> true
    is ChainMetricReading.BlockProduction -> false
}
