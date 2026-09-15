package io.paritytech.polkadotapp.feature_become_citizen_impl.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.network.updaters.BlockNumberUpdater
import io.paritytech.polkadotapp.chains.network.updaters.BlockTimeUpdater
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.network.updaters.system.UpdateSystemFactory
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.common.data.worker.stateMachine.impl.PrefsWorkerStateMachineLocalSessionFactory
import io.paritytech.polkadotapp.feature_account_api.data.CandidateAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_become_citizen_api.data.signer.PostApplyOriginProvider
import io.paritytech.polkadotapp.feature_become_citizen_api.data.updaters.BecomeCitizenUpdateSystem
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.referrals.ReferralInstallHandler
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceLocalSession
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceStateFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.ProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage.ReferralInstallHandlerStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.updaters.CandidateUpdater
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.updaters.ConfigurationUpdater
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.updaters.PeopleUpdater
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.updaters.ReferralTicketUpdater
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals.RealReferralInstallHandler
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals.ReferralTicketDeeplinkMapper
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.SelectedTattooRenderer
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.TransactionStorageAuthorizationUpdaterFactory

@Module
@InstallIn(SingletonComponent::class)
class BecomeCitizenProvidesModule {
    @Provides
    fun providePostApplyOriginProvider(
        proofOfInkOriginsFactory: ProofOfInkOriginsFactory
    ): PostApplyOriginProvider = proofOfInkOriginsFactory.foreground

    @Provides
    fun provideReferralInstallHandler(
        context: Context,
        referralInstallHandlerStorage: ReferralInstallHandlerStorage,
        referralTicketDeeplinkMapper: ReferralTicketDeeplinkMapper
    ): ReferralInstallHandler = RealReferralInstallHandler(
        context,
        referralInstallHandlerStorage,
        referralTicketDeeplinkMapper
    )

    @Provides
    fun provideUploadEvidenceLocalSession(
        factory: PrefsWorkerStateMachineLocalSessionFactory,
        stateFactory: UploadEvidenceStateFactory,
    ): UploadEvidenceLocalSession {
        return factory.create(uniquePrefix = "EvidenceUpload", stateFactory)
    }

    @Provides
    fun provideCandidateUpdater(
        @CandidateAccount scope: Updater.NoChainScope<MetaAccount>,
        chainRegistry: ChainRegistry,
        storageCache: StorageCache
    ): CandidateUpdater = CandidateUpdater(scope, chainRegistry, storageCache)

    @Provides
    fun provideBecomeCitizenUpdaters(
        @CandidateAccount candidateAccountScope: Updater.NoChainScope<MetaAccount>,
        updateSystemFactory: UpdateSystemFactory,
        candidateUpdater: CandidateUpdater,
        configurationUpdater: ConfigurationUpdater,
        peopleUpdater: PeopleUpdater,
        referralTicketUpdater: ReferralTicketUpdater,
        transactionStorageAuthorizationUpdaterFactory: TransactionStorageAuthorizationUpdaterFactory,
        blockNumberUpdater: BlockNumberUpdater,
        blockTimeUpdater: BlockTimeUpdater,
        knownChains: KnownChains
    ): BecomeCitizenUpdateSystem {
        val transactionStorageAuthorizationUpdater = transactionStorageAuthorizationUpdaterFactory.create(candidateAccountScope)

        val peopleUpdateSystem = updateSystemFactory.createConstantSingleChain(
            listOf(
                candidateUpdater,
                configurationUpdater,
                peopleUpdater,
                referralTicketUpdater,
                blockNumberUpdater
            ),
            knownChains.people
        )

        val bulletInUpdateSystem = updateSystemFactory.createConstantSingleChain(
            listOf(
                transactionStorageAuthorizationUpdater,
                blockNumberUpdater,
                blockTimeUpdater
            ),
            knownChains.bulletIn
        )

        return BecomeCitizenUpdateSystem(peopleUpdateSystem, bulletInUpdateSystem)
    }

    @Provides
    fun provideSelectedTattooRenderer(
        @ApplicationContext context: Context,
        tattooImageLoader: TattooImageLoader
    ) = SelectedTattooRenderer(context, tattooImageLoader)
}
