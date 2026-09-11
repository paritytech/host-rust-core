package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import javax.inject.Inject
import kotlin.math.roundToInt

/**
 * Scores best-block liveness. The signal is the worse of the 10-block moving-average latency and the
 * raw time since the last block (the acute-stall guard), each mapped through the same plateau→zero
 * curve relative to the chain's expected block time. Both null (freshly connected, nothing observed
 * yet) is treated optimistically as perfect so the ring starts full and self-corrects.
 */
class LivenessScorer @Inject constructor() {
    fun score(
        expectedBlockTimeMillis: Long,
        averageLatencyMillis: Long?,
        elapsedSinceLastBlockMillis: Long?,
    ): ChainHealthScore {
        val candidates = listOfNotNull(averageLatencyMillis, elapsedSinceLastBlockMillis)
        if (candidates.isEmpty()) return ChainHealthScore.Perfect

        val plateau = expectedBlockTimeMillis * ChainHealthThresholds.LIVENESS_PLATEAU_MULTIPLIER
        val zero = expectedBlockTimeMillis * ChainHealthThresholds.LIVENESS_ZERO_MULTIPLIER
        val worst = candidates.max().toDouble()

        return ChainHealthScore.coerced(linearScore(worst, plateau, zero))
    }

    private fun linearScore(value: Double, plateau: Double, zero: Double): Int = when {
        value <= plateau -> ChainHealthScore.MAX_VALUE
        value >= zero -> ChainHealthScore.MIN_VALUE
        else -> (ChainHealthScore.MAX_VALUE * (zero - value) / (zero - plateau)).roundToInt()
    }
}
