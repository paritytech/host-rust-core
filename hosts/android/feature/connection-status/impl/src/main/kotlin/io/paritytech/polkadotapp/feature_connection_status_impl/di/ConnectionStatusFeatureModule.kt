package io.paritytech.polkadotapp.feature_connection_status_impl.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import io.paritytech.polkadotapp.feature_connection_status_api.domain.ChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthMixin
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.RealChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe.BlockLivenessProbe
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe.ChainHealthProbe
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe.FinalityGapProbe
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe.PendingRequestLatencyProbe
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe.ResponseLatencyProbe
import io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin.RealChainHealthMixinFactory
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
interface ConnectionStatusFeatureModule {
    @Binds
    @Singleton
    fun bindChainHealthMonitor(impl: RealChainHealthMonitor): ChainHealthMonitor

    @Binds
    fun bindChainHealthMixinFactory(impl: RealChainHealthMixinFactory): ChainHealthMixin.Factory

    @Binds
    @IntoSet
    fun bindBlockLivenessProbe(impl: BlockLivenessProbe): ChainHealthProbe

    @Binds
    @IntoSet
    fun bindFinalityGapProbe(impl: FinalityGapProbe): ChainHealthProbe

    @Binds
    @IntoSet
    fun bindPendingRequestLatencyProbe(impl: PendingRequestLatencyProbe): ChainHealthProbe

    @Binds
    @IntoSet
    fun bindResponseLatencyProbe(impl: ResponseLatencyProbe): ChainHealthProbe
}
