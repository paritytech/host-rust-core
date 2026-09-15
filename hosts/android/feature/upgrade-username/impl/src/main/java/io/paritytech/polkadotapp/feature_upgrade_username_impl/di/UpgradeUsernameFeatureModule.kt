package io.paritytech.polkadotapp.feature_upgrade_username_impl.di

import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.ElementsIntoSet
import io.paritytech.polkadotapp.feature_people_api.data.AliasContextProvider
import io.paritytech.polkadotapp.feature_people_api.data.SetAliasContext
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.bot.UsernameUpgradedMessageProcessor
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.CheckUsernameAvailabilityUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.ReadyToUpgradeUsernameUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_impl.data.ResourcesContextProvider
import io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.bot.RealUsernameUpgradedMessageProcessor
import io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.interactor.RealUsernameUpgradeInteractor
import io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.interactor.UsernameUpgradeInteractor
import io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.usecase.RealCheckUsernameAvailabilityUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.usecase.RealReadyToUpgradeUsernameUseCase

@Module
@InstallIn(SingletonComponent::class)
interface UpgradeUsernameFeatureModule {
    @Binds
    fun bindReadyToUpgradeUsernameUseCase(implementation: RealReadyToUpgradeUsernameUseCase): ReadyToUpgradeUsernameUseCase

    @Binds
    fun bindUsernameUpgradeInteractor(impl: RealUsernameUpgradeInteractor): UsernameUpgradeInteractor

    @Binds
    fun bindCheckUsernameAvailabilityUseCase(impl: RealCheckUsernameAvailabilityUseCase): CheckUsernameAvailabilityUseCase

    @Binds
    fun bindUsernameUpgradedMessageProcessor(impl: RealUsernameUpgradedMessageProcessor): UsernameUpgradedMessageProcessor

    companion object {
        @Provides
        @ElementsIntoSet
        @SetAliasContext
        fun provideResourcesContext(resourcesContextProvider: ResourcesContextProvider): Set<AliasContextProvider> {
            return setOf(AliasContextProvider { resourcesContextProvider.context() })
        }
    }
}
