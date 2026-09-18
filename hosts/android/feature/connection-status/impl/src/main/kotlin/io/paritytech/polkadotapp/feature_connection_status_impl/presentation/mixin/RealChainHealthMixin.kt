package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.common.presentation.subscribeIsForeground
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_connection_status_api.domain.ChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealth
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainGlyph
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicatorsModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthItemModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthMixin
import io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin.mapper.toIndicator
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlin.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
internal class RealChainHealthMixin(
    scope: ComputationalScope,
    monitor: ChainHealthMonitor,
    private val knownChains: KnownChains,
    appLifecycleObserver: AppLifecycleObserver,
) : ChainHealthMixin, ComputationalScope by scope {
    override val model: StateFlow<ChainHealthIndicatorsModel> = appLifecycleObserver.subscribeIsForeground()
        .flatMapLatest { inForeground ->
            if (inForeground) monitor.observeChainsHealth().map { healths -> healths.toModel() } else emptyFlow()
        }
        .stateInBackground(SharingStarted.Eagerly, EMPTY_MODEL)

    private fun List<ChainHealth>.toModel(): ChainHealthIndicatorsModel =
        ChainHealthIndicatorsModel(map(::toItem).toImmutableList())

    private fun toItem(health: ChainHealth): ChainHealthItemModel = ChainHealthItemModel(
        chainName = health.chainName,
        glyph = glyphFor(health.chainId),
        indicator = health.toIndicator(),
        lastBlockAt = health.lastBlockAt(),
    )

    private fun ChainHealth.lastBlockAt(): Instant? = readings
        .filterIsInstance<ChainMetricReading.BlockProduction>()
        .firstNotNullOfOrNull { it.lastBlockAt }

    private fun glyphFor(chainId: ChainId): ChainGlyph = when (chainId) {
        knownChains.assetHub -> ChainGlyph.AssetHub
        knownChains.bulletIn -> ChainGlyph.Bulletin
        else -> ChainGlyph.People
    }

    private companion object {
        val EMPTY_MODEL = ChainHealthIndicatorsModel(persistentListOf())
    }
}
