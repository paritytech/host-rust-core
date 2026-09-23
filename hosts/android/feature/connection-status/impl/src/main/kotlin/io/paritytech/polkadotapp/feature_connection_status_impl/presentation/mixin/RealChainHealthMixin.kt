package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.common.presentation.subscribeIsForeground
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_connection_status_api.domain.ChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealth
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainGlyph
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicatorsModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthItemModel
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthMixin
import io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin.mapper.isAnchorPending
import io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin.mapper.toIndicator
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.scan

@OptIn(ExperimentalCoroutinesApi::class)
internal class RealChainHealthMixin(
    scope: ComputationalScope,
    monitor: ChainHealthMonitor,
    private val knownChains: KnownChains,
    appLifecycleObserver: AppLifecycleObserver,
) : ChainHealthMixin, ComputationalScope by scope {
    override val model: StateFlow<ChainHealthIndicatorsModel> = appLifecycleObserver.subscribeIsForeground()
        .flatMapLatest { inForeground -> if (inForeground) monitor.observeChainsHealth() else emptyFlow() }
        .scan(EMPTY_MODEL) { previous, healths -> healths.toModel(previous) }
        .stateInBackground(SharingStarted.Eagerly, EMPTY_MODEL)

    private fun List<ChainHealth>.toModel(previous: ChainHealthIndicatorsModel): ChainHealthIndicatorsModel =
        ChainHealthIndicatorsModel(map { health -> toItem(health, previous) }.toImmutableList())

    private fun toItem(health: ChainHealth, previous: ChainHealthIndicatorsModel): ChainHealthItemModel {
        val indicator = health.toIndicator()
        val shown = previous.chains.firstOrNull { it.chainId == health.chainId }
            // While a connected chain is being asked how fast it has been going, what it showed before stands.
            ?.takeIf { indicator == UNMEASURED && health.isAnchorPending() && it.indicator.isProduction() }
            ?.indicator
            ?: indicator

        return ChainHealthItemModel(
            chainId = health.chainId,
            chainName = health.chainName,
            glyph = glyphFor(health.chainId),
            indicator = shown,
        )
    }

    private fun ChainHealthIndicator.isProduction(): Boolean = when (this) {
        is ChainHealthIndicator.Healthy, is ChainHealthIndicator.Production, ChainHealthIndicator.Outage -> true
        ChainHealthIndicator.Connecting, ChainHealthIndicator.Disconnected, ChainHealthIndicator.Offline -> false
    }

    private fun glyphFor(chainId: ChainId): ChainGlyph = when (chainId) {
        knownChains.assetHub -> ChainGlyph.AssetHub
        knownChains.bulletIn -> ChainGlyph.Bulletin
        else -> ChainGlyph.People
    }

    private companion object {
        val EMPTY_MODEL = ChainHealthIndicatorsModel(persistentListOf())
        val UNMEASURED = ChainHealthIndicator.Healthy(liveness = null)
    }
}
