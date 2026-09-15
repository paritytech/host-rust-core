package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_connection_status_api.domain.ChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthMixin
import javax.inject.Inject

class RealChainHealthMixinFactory @Inject constructor(
    private val monitor: ChainHealthMonitor,
    private val knownChains: KnownChains,
) : ChainHealthMixin.Factory {
    override fun create(scope: ComputationalScope): ChainHealthMixin =
        RealChainHealthMixin(scope, monitor, knownChains)
}
