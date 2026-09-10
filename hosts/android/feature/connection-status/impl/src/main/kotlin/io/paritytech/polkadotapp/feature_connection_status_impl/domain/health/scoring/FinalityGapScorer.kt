package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import javax.inject.Inject
import kotlin.math.roundToInt

/**
 * Scores the finality gap (best - finalized, in blocks) on its own curve — deliberately not the
 * block-time-relative curve used for liveness, since finality is structurally several blocks behind
 * even when healthy. A stalling finality grows the gap, so gap magnitude captures monotonic stall.
 */
class FinalityGapScorer @Inject constructor() {
    /**
     * @param idealGap gap at or below which the chain scores full marks.
     * @param outageGap gap at or above which the chain scores zero.
     */
    fun score(gapBlocks: Int, idealGap: Int, outageGap: Int): ChainHealthScore {
        val gap = gapBlocks.coerceAtLeast(0)

        val score = when {
            gap <= idealGap -> ChainHealthScore.MAX_VALUE
            gap >= outageGap -> ChainHealthScore.MIN_VALUE
            else -> (ChainHealthScore.MAX_VALUE.toDouble() * (outageGap - gap) / (outageGap - idealGap)).roundToInt()
        }
        return ChainHealthScore.coerced(score)
    }
}
