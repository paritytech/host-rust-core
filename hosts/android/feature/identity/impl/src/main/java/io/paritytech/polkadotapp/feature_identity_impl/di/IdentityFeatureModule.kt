package io.paritytech.polkadotapp.feature_identity_impl.di

import dagger.*
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.ElementsIntoSet
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_identity_api.data.repository.UserIdentityRepository
import io.paritytech.polkadotapp.feature_identity_api.data.storage.ClaimedUsernameStorage
import io.paritytech.polkadotapp.feature_identity_api.data.storage.CredentialClaimedStorage
import io.paritytech.polkadotapp.feature_identity_api.data.updaters.CredentialsUpdaters
import io.paritytech.polkadotapp.feature_identity_api.domain.CredentialPlatformsStateUseCase
import io.paritytech.polkadotapp.feature_identity_impl.data.IDENTITY
import io.paritytech.polkadotapp.feature_identity_impl.data.repository.RealUserIdentityRepository
import io.paritytech.polkadotapp.feature_identity_impl.data.storage.RealClaimedUsernameStorage
import io.paritytech.polkadotapp.feature_identity_impl.data.storage.RealCredentialClaimedStorage
import io.paritytech.polkadotapp.feature_identity_impl.data.updaters.IdentityRegistrationUpdater
import io.paritytech.polkadotapp.feature_identity_impl.data.updaters.PersonalIdentityUpdater
import io.paritytech.polkadotapp.feature_identity_impl.domain.RealCredentialPlatformsStateUseCase
import io.paritytech.polkadotapp.feature_identity_impl.domain.interactor.CredentialsAddInteractor
import io.paritytech.polkadotapp.feature_identity_impl.domain.interactor.CredentialsListInteractor
import io.paritytech.polkadotapp.feature_identity_impl.domain.interactor.RealCredentialsAddInteractor
import io.paritytech.polkadotapp.feature_identity_impl.domain.interactor.RealCredentialsListInteractor
import io.paritytech.polkadotapp.feature_people_api.data.AliasContextProvider
import io.paritytech.polkadotapp.feature_people_api.data.SetAliasContext

@Module
@InstallIn(SingletonComponent::class)
interface IdentityFeatureModule {
    @Binds
    fun bindCredentialsListInteractor(impl: RealCredentialsListInteractor): CredentialsListInteractor

    @Binds
    fun bindInteractor(impl: RealCredentialsAddInteractor): CredentialsAddInteractor

    @Binds
    fun bindCredentialClaimedStorage(impl: RealCredentialClaimedStorage): CredentialClaimedStorage

    @Binds
    fun bindClaimedUsernameStorage(impl: RealClaimedUsernameStorage): ClaimedUsernameStorage

    @Binds
    fun bindUserIdentityRepository(impl: RealUserIdentityRepository): UserIdentityRepository

    @Binds
    fun bindCredentialPlatformsStateUseCase(impl: RealCredentialPlatformsStateUseCase): CredentialPlatformsStateUseCase

    companion object {
        @Provides
        @ElementsIntoSet
        @SetAliasContext
        fun provideIdentityContext(): Set<AliasContextProvider> = setOf(AliasContextProvider { BandersnatchContext.IDENTITY })

        @Provides
        fun provideCredentialsUpdaters(
            identityRegistrationUpdater: IdentityRegistrationUpdater,
            personalIdentityUpdater: PersonalIdentityUpdater,
        ): CredentialsUpdaters {
            val peopleChainUpdaters = listOf(identityRegistrationUpdater, personalIdentityUpdater)
            return CredentialsUpdaters(peopleChainUpdaters)
        }
    }
}
