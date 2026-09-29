package io.paritytech.polkadotapp.feature_become_citizen_impl.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoSet
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.CandidateStateRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.RealCandidateStateRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.data.upload.EvidenceUploadStarter
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.CandidateDepositAssetProvider
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.CitizenshipApplyUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.metadataFetcher.RealTattooFamilyMetadataFetcher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.metadataFetcher.TattooFamilyMetadataFetcher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.notifications.EvidenceNotificationsPublisher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.notifications.RealEvidenceNotificationsPublisher
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.RealEvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.RealEvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.EvidenceUploader
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.RealEvidenceUploadStarter
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload.RealEvidenceUploader
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.repository.MobRuleRepository
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.repository.RealMobRuleRepository
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.repository.RealTattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.ProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.proofOfInk.RealProofOfInkOriginsFactory
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage.EncryptedReferralTicketsStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage.RealReferralInstallHandlerStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage.ReferralInstallHandlerStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.storage.ReferralTicketsStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.RealCandidateDepositAssetProvider
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.RealTattooBotInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.TattooBotInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.candidateState.RealCitizenshipApplyUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.candidateState.RealTattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.dim.Dim1CommitmentHandler
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.RealTattooFamilyDetailsInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.TattooFamilyDetailsInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals.RealReferralTicketDeeplinkMapper
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.referrals.ReferralTicketDeeplinkMapper
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo.InstructionsAttachmentUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo.RealInstructionsAttachmentUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.TattooBot
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.tattooLoader.RealTattooImageLoader
import io.paritytech.polkadotapp.feature_chats_api.domain.extension.ChatExtension
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimCommitmentHandler
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
internal interface BecomeCitizenFeatureModule {
    @Binds
    fun bindReferralTicketDeeplinkMapper(impl: RealReferralTicketDeeplinkMapper): ReferralTicketDeeplinkMapper

    @Binds
    @Singleton
    @CandidateDepositAssetProvider
    fun bindCandidateDepositAssetProvider(impl: RealCandidateDepositAssetProvider): ChainAssetProvider

    @Binds
    @Singleton
    @IntoSet
    fun bindTattooBot(impl: TattooBot): ChatExtension

    @Binds
    fun bindReferralTicketStorage(impl: EncryptedReferralTicketsStorage): ReferralTicketsStorage

    @Binds
    fun bindReferralInstallHandlerStorage(impl: RealReferralInstallHandlerStorage): ReferralInstallHandlerStorage

    @Binds
    fun bindTattooProgressStateUseCase(impl: RealTattooProgressStateUseCase): TattooProgressStateUseCase

    @Binds
    fun bindTattooImageLoader(impl: RealTattooImageLoader): TattooImageLoader

    @Binds
    fun bindTattooRepository(impl: RealTattooRepository): TattooRepository

    @Binds
    fun bindTattooFamilyMetadataFetcher(impl: RealTattooFamilyMetadataFetcher): TattooFamilyMetadataFetcher

    @Binds
    fun bindCandidateStateRepository(impl: RealCandidateStateRepository): CandidateStateRepository

    @Binds
    fun bindCitizenshipApplyUseCase(impl: RealCitizenshipApplyUseCase): CitizenshipApplyUseCase

    @Binds
    fun bindEvidenceUploadStarter(impl: RealEvidenceUploadStarter): EvidenceUploadStarter

    @Binds
    fun bindEvidenceStorage(impl: RealEvidenceStorage): EvidenceStorage

    @Binds
    fun bindEvidenceUploader(impl: RealEvidenceUploader): EvidenceUploader

    @Binds
    fun bindTattooBotInteractor(impl: RealTattooBotInteractor): TattooBotInteractor

    @Binds
    fun bindProofOfInkOriginsFactory(impl: RealProofOfInkOriginsFactory): ProofOfInkOriginsFactory

    @Binds
    fun bindEvidenceLocalStateStorage(impl: RealEvidenceLocalStateStorage): EvidenceLocalStateStorage

    @Binds
    fun bindTattooFamilyDetailsInteractor(impl: RealTattooFamilyDetailsInteractor): TattooFamilyDetailsInteractor

    @Binds
    @IntoSet
    fun bindDim1CommitmentHandler(impl: Dim1CommitmentHandler): DimCommitmentHandler

    @Binds
    fun bindMobRuleRepository(impl: RealMobRuleRepository): MobRuleRepository

    @Binds
    fun bindInstructionsAttachmentUseCase(impl: RealInstructionsAttachmentUseCase): InstructionsAttachmentUseCase

    @Binds
    fun bindEvidenceNotificationsPublisher(impl: RealEvidenceNotificationsPublisher): EvidenceNotificationsPublisher
}
