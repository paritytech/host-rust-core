package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_connection_status_api.domain.ChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealth
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainGlyph
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthBarModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthItemModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthMixin
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map

internal class RealChainHealthMixin(
    scope: ComputationalScope,
    monitor: ChainHealthMonitor,
    private val knownChains: KnownChains,
) : ChainHealthMixin, ComputationalScope by scope {
    override val model: StateFlow<ChainHealthBarModel> = monitor.observeChainsHealth()
        .map { healths -> healths.toBarModel() }
        .stateInBackground(SharingStarted.WhileSubscribed(), EMPTY_MODEL)

    private fun List<ChainHealth>.toBarModel(): ChainHealthBarModel =
        ChainHealthBarModel(map(::toItem).toImmutableList())

    private fun toItem(health: ChainHealth): ChainHealthItemModel = ChainHealthItemModel(
        chainId = health.chainId,
        chainName = health.chainName,
        glyph = glyphFor(health.chainId),
        connection = health.connection,
        score = health.score,
        readings = health.readings.toImmutableList(),
    )

    private fun glyphFor(chainId: ChainId): ChainGlyph = when (chainId) {
        knownChains.assetHub -> ChainGlyph.AssetHub
        knownChains.bulletIn -> ChainGlyph.Bulletin
        else -> ChainGlyph.People
    }

    private companion object {
        val EMPTY_MODEL = ChainHealthBarModel(persistentListOf())
    }
}
