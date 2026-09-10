package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.ChainHealthThresholds
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.FinalityGapScorer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import javax.inject.Inject

/**
 * Gap between the best and finalized block. A stalling finality grows the gap, so gap magnitude alone
 * reflects a monotonic finality stall. Thresholds are read per-chain from `Chain.additional`, falling
 * back to the defaults in [ChainHealthThresholds].
 */
class FinalityGapProbe @Inject constructor(
    private val finalityGapScorer: FinalityGapScorer,
) : ChainHealthProbe {
    override fun observe(context: ChainMetricContext): Flow<ChainMetricReading> {
        val idealGap = context.chain.additional?.finalityGapIdeal ?: ChainHealthThresholds.FINALITY_GAP_IDEAL
        val outageGap = context.chain.additional?.finalityGapOutage ?: ChainHealthThresholds.FINALITY_GAP_OUTAGE

        return combine(
            context.bestBlockNumber,
            context.finalizedBlockNumber,
        ) { best, finalized ->
            val gap = (best - finalized).coerceAtLeast(0)

            ChainMetricReading.FinalityGap(
                gapBlocks = gap,
                targetBlocks = idealGap,
                score = finalityGapScorer.score(gap, idealGap, outageGap),
            )
        }.distinctUntilChanged()
    }
}
