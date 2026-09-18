package io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin

import androidx.compose.runtime.Immutable
import kotlinx.collections.immutable.ImmutableList
import kotlin.time.Instant

enum class ChainGlyph {
    People,
    AssetHub,
    Bulletin,
}

/**
 * What one chain's indicator draws, in the priority the health rules give them: connectivity first,
 * then block production, then connection speed; [Healthy] only when none of them has anything to say.
 */
sealed interface ChainHealthIndicator {
    data object Healthy : ChainHealthIndicator

    data object Outage : ChainHealthIndicator

    /** [arc] is the share of the ring the indicator fills; it travels inside the [speed] band's quarter. */
    data class ConnectionSpeed(
        val speed: Speed,
        val arc: Float,
    ) : ChainHealthIndicator

    data object Connecting : ChainHealthIndicator

    /** No node responding, a connected node that no longer answers, or a device with no internet. */
    data object Disconnected : ChainHealthIndicator

    /** How far the chain has fallen from a speed that needs no comment; the band above these is [Healthy]. */
    enum class Speed {
        Good,
        Fair,
        Low,
    }
}

@Immutable
data class ChainHealthIndicatorsModel(
    val chains: ImmutableList<ChainHealthItemModel>,
)

@Immutable
data class ChainHealthItemModel(
    val chainName: String,
    val glyph: ChainGlyph,
    val indicator: ChainHealthIndicator,
    /** When the last block landed. The view ages it on its own tick, so a stalled chain keeps counting. */
    val lastBlockAt: Instant?,
)
