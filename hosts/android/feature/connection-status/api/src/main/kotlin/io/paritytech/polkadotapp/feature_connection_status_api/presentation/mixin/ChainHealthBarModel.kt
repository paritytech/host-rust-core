package io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import kotlinx.collections.immutable.ImmutableList

/** Stable identity for a monitored chain's inner glyph; the widget maps each to a drawable. */
enum class ChainGlyph {
    People,
    AssetHub,
    Bulletin,
}

@Immutable
data class ChainHealthBarModel(
    val chains: ImmutableList<ChainHealthItemModel>,
)

@Immutable
data class ChainHealthItemModel(
    val chainId: ChainId,
    val chainName: String,
    val glyph: ChainGlyph,
    val connection: ChainConnectionPresentation,
    val score: ChainHealthScore,
    val readings: ImmutableList<ChainMetricReading>,
)
