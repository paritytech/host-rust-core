package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import javax.inject.Inject
import kotlin.math.roundToInt

/**
 * Scores the age of the oldest pending socket request: full marks while it stays under the ideal,
 * decaying linearly to zero by the outage threshold.
 */
class LatencyScorer @Inject constructor() {
    fun score(oldestPendingMillis: Long, idealMillis: Long, outageMillis: Long): ChainHealthScore {
        val value = oldestPendingMillis.coerceAtLeast(0)

        val score = when {
            value <= idealMillis -> ChainHealthScore.MAX_VALUE
            value >= outageMillis -> ChainHealthScore.MIN_VALUE
            else -> (ChainHealthScore.MAX_VALUE * (outageMillis - value).toDouble() / (outageMillis - idealMillis)).roundToInt()
        }
        return ChainHealthScore.coerced(score)
    }
}
