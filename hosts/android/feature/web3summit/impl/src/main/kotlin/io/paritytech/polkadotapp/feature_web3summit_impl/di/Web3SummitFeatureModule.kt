package io.paritytech.polkadotapp.feature_web3summit_impl.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import io.paritytech.polkadotapp.feature_transactions.api.data.extensions.DefaultTransactionExtensionProvider
import io.paritytech.polkadotapp.feature_web3summit_api.domain.ObserveWeb3SummitEndedUseCase
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.RemoteConfigWeb3SummitConfigProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.data.config.Web3SummitConfigProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.data.contract.RealWeb3SummitContractRepository
import io.paritytech.polkadotapp.feature_web3summit_impl.data.contract.Web3SummitContractRepository
import io.paritytech.polkadotapp.feature_web3summit_impl.data.extensions.Web3SummitAuthExtensionProvider
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.RealObserveWeb3SummitEndedUseCase
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.warmUp.RealWeb3SummitWarmUpService
import io.paritytech.polkadotapp.feature_web3summit_impl.domain.warmUp.Web3SummitWarmUpService
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
interface Web3SummitFeatureModule {
    @Binds
    @IntoSet
    fun bindW3SAuthExtensionProvider(impl: Web3SummitAuthExtensionProvider): DefaultTransactionExtensionProvider

    @Binds
    @Singleton
    fun bindWeb3SummitContractRepository(impl: RealWeb3SummitContractRepository): Web3SummitContractRepository

    @Binds
    fun bindObserveWeb3SummitEndedUseCase(impl: RealObserveWeb3SummitEndedUseCase): ObserveWeb3SummitEndedUseCase

    @Binds
    @Singleton
    fun bindWeb3SummitConfigProvider(impl: RemoteConfigWeb3SummitConfigProvider): Web3SummitConfigProvider

    @Binds
    fun bindWeb3SummitWarmUpService(impl: RealWeb3SummitWarmUpService): Web3SummitWarmUpService
}
