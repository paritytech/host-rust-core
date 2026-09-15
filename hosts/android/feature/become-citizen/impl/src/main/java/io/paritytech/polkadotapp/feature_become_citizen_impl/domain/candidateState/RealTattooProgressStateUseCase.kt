package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.candidateState

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.chains.repository.ChainStateRepository
import io.paritytech.polkadotapp.chains.repository.blockDurationEstimatorFlow
import io.paritytech.polkadotapp.chains.util.BlockDurationEstimator
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.Fraction.Companion.toFraction
import io.paritytech.polkadotapp.common.utils.FractionUnit
import io.paritytech.polkadotapp.common.utils.combineToTriple
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.wrapIntoResult
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.ProofOfInkPerson
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.CandidateStateRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooCommitmentExpiration
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.ChunkIndex
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UnrecoverableFailure
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceLocalSession
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.UploadEvidenceState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AllDone
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitExtendAllocationConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitPhotoChunkConfirmation
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitPhotoMetadataConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitProvenCandidacyState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitStorageAuthorizationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitVideoChunkConfirmation
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.AwaitVideoMetadataConfirmationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.ExtendAllocationState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.RegisterPersonKeyState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StartPersonSetupState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StorePhotoChunkState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StorePhotoMetadataState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StoreVideoChunkState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.StoreVideoMetadataState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.SubmitPhotoHashState
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.state.strechunkstate.SubmitVideoHashState
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_transaction_storage_api.domain.TransactionStorageRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import timber.log.Timber
import javax.inject.Inject

class RealTattooProgressStateUseCase @Inject constructor(
    private val candidateStateRepository: CandidateStateRepository,
    private val chainStateRepository: ChainStateRepository,
    private val accountRepository: AccountRepository,
    private val uploadEvidenceLocalSession: UploadEvidenceLocalSession,
    private val transactionStorageRepository: TransactionStorageRepository,
    private val coroutineDispatchers: CoroutineDispatchers,
    private val personIdRepository: PersonIdRepository,
    private val chainRegistry: ChainRegistry
) : TattooProgressStateUseCase {
    override fun tattooProgressStateFlow(): Flow<Result<TattooProgressState>> {
        return flowOf { accountRepository.getCandidateAccount() }
            .flatMapLatest { metaAccount ->
                val chain = chainRegistry.peopleChain()
                val accountId = metaAccount.accountIdIn(chain)

                createTattooProgressFlow(accountId, chain)
            }
            .wrapIntoResult()
            .logFailure("Failed to construct candidateStateFlow")
    }

    override suspend fun getTattooProgressState(): Result<TattooProgressState> {
        return tattooProgressStateFlow()
            .flowOn(coroutineDispatchers.io)
            .first()
    }

    private suspend fun createTattooProgressFlow(accountId: AccountId, chain: Chain): Flow<TattooProgressState> {
        return combineToTriple(
            candidateStateRepository.proofOfInkCandidateFlow(accountId, chain.id),
            dim1RecognizedPerson(chain),
            uploadEvidenceLocalSession.currentStateFlow(),
        ).flatMapLatest { (candidateState, person, evidenceUploadingState) ->
            createTattooProgressFlow(accountId, candidateState, person, evidenceUploadingState)
        }
    }

    private fun dim1RecognizedPerson(chain: Chain): Flow<RecognizedPersonInfo?> {
        return personIdRepository.personIdFlow().flatMapLatest { personId ->
            if (personId == null) return@flatMapLatest flowOf(null)

            candidateStateRepository.personFlow(chain.id, personId)
                .map { proofOfInkPerson ->
                    proofOfInkPerson?.let { RecognizedPersonInfo(personId, proofOfInkPerson) }
                }
        }
    }

    private suspend fun createTattooProgressFlow(
        accountId: AccountId,
        candidate: ProofOfInkCandidate?,
        personInfo: RecognizedPersonInfo?,
        evidenceState: UploadEvidenceState?,
    ): Flow<TattooProgressState> {
        return flowOfAll {
            when {
                // User has obtained dim1-recognized personhood
                personInfo != null -> flowOf(personInfo.toRecognizedPersonState())

                // We know we have started the uploading - use local status
                evidenceState != null -> flowOf(evidenceState.toCitizenshipApplicationState())

                // User has not fully yet onboarded nor has it started the onboarding
                candidate == null -> flowOf(TattooProgressState.NotStarted)

                // User has already selected a tattoo but did not provide evidence yet
                candidate is ProofOfInkCandidate.Selected -> createCommittedStateFlow(accountId, candidate)

                candidate is ProofOfInkCandidate.Applied -> flowOf(TattooProgressState.Applied(candidate.entropy))

                candidate is ProofOfInkCandidate.Proven -> flowOf(TattooProgressState.RegisteringPerson)

                else -> flowOf(TattooProgressState.Unknown)
            }
        }
    }

    private fun RecognizedPersonInfo.toRecognizedPersonState(): TattooProgressState.RecognizedPerson {
        return TattooProgressState.RecognizedPerson(
            personId = personId,
            activeReferrals = personData.activeReferrals,
            banned = personData.banned,
            pendingReferralRewards = personData.pendingReferralRewards,
            allowedReferralTickets = personData.allowedReferralTickets
        )
    }

    private suspend fun createCommittedStateFlow(
        accountId: AccountId,
        candidate: ProofOfInkCandidate.Selected
    ): Flow<TattooProgressState.Committed> {
        val bulletInChainId = chainRegistry.knownChains.bulletIn

        return combine(
            chainStateRepository.blockDurationEstimatorFlow(bulletInChainId),
            transactionStorageRepository.accountAuthorizationDeadlineFlow(bulletInChainId, accountId)
        ) { blockEstimator, expirationBlock ->
            val expiration = blockEstimator.expirationOf(expirationBlock)
            TattooProgressState.Committed(expiration = expiration, tattooId = candidate.tattooId)
        }
    }

    private fun UploadEvidenceState.toCitizenshipApplicationState(): TattooProgressState {
        val progressStatus: TattooProgressState.UploadingEvidence.Status?
        val evidenceType: EvidenceType?

        when (this) {
            is AwaitStorageAuthorizationState -> {
                progressStatus = TattooProgressState.UploadingEvidence.Status.WaitingForStorageAllocation
                evidenceType = EvidenceType.PHOTO
            }

            is StorePhotoChunkState -> {
                progressStatus = chunkIndex.toUploadingStatus()
                evidenceType = EvidenceType.PHOTO
            }
            is AwaitPhotoChunkConfirmation -> {
                progressStatus = chunkIndex.toUploadingStatus()
                evidenceType = EvidenceType.PHOTO
            }

            is StorePhotoMetadataState,
            is AwaitPhotoMetadataConfirmationState,
            is SubmitPhotoHashState -> {
                progressStatus = TattooProgressState.UploadingEvidence.Status.FinalizingUploading
                evidenceType = EvidenceType.PHOTO
            }

            is ExtendAllocationState -> {
                progressStatus = TattooProgressState.UploadingEvidence.Status.WaitingForJudgement
                evidenceType = EvidenceType.PHOTO
            }
            is AwaitExtendAllocationConfirmationState -> {
                progressStatus = TattooProgressState.UploadingEvidence.Status.WaitingForStorageAllocation
                evidenceType = EvidenceType.VIDEO
            }

            is StoreVideoChunkState -> {
                progressStatus = chunkIndex.toUploadingStatus()
                evidenceType = EvidenceType.VIDEO
            }
            is AwaitVideoChunkConfirmation -> {
                progressStatus = chunkIndex.toUploadingStatus()
                evidenceType = EvidenceType.VIDEO
            }

            is StoreVideoMetadataState,
            is AwaitVideoMetadataConfirmationState,
            is SubmitVideoHashState -> {
                progressStatus = TattooProgressState.UploadingEvidence.Status.FinalizingUploading
                evidenceType = EvidenceType.VIDEO
            }

            is AwaitProvenCandidacyState -> {
                progressStatus = TattooProgressState.UploadingEvidence.Status.WaitingForJudgement
                evidenceType = EvidenceType.VIDEO
            }

            is AllDone -> {
                progressStatus = null
                evidenceType = null
            }

            is RegisterPersonKeyState,
            is StartPersonSetupState -> return TattooProgressState.RegisteringPerson
            is UnrecoverableFailure -> return TattooProgressState.UnrecoverableFailure(params.reason)

            else -> throw IllegalStateException("Unsupported UploadEvidenceState child: ${this.javaClass.simpleName}")
        }

        return if (progressStatus != null && evidenceType != null) {
            TattooProgressState.UploadingEvidence(evidenceType, progressStatus)
        } else {
            Timber.e("The uploading process is All done, but no person id got obtained")

            TattooProgressState.Unknown
        }
    }

    @Suppress("IfThenToElvis")
    private fun TransactionStorageRepository.accountAuthorizationDeadlineFlow(chainId: ChainId, accountId: AccountId): Flow<BlockNumber> {
        return subscribeAuthorization(chainId, accountId, CacheableDataConsistency.CAN_BE_STALE).map { storageAuthorization ->
            if (storageAuthorization != null) {
                storageAuthorization.expiration
            } else {
                chainStateRepository.currentBlock(chainId) + authorizationPeriod(chainId).getOrThrow()
            }
        }.distinctUntilChanged()
    }

    private fun ChunkIndex.toUploadingStatus(): TattooProgressState.UploadingEvidence.Status.UploadingInProgress {
        val fraction = index.toDouble() / totalChunks
        return TattooProgressState.UploadingEvidence.Status.UploadingInProgress(fraction.toFraction(FractionUnit.FRACTION))
    }

    private fun BlockDurationEstimator.expirationOf(expirationBlock: BlockNumber): TattooCommitmentExpiration {
        return TattooCommitmentExpiration(
            expiresIn = durationUntil(expirationBlock),
            expiresAt = timestampAt(expirationBlock),
            hasExpired = currentBlock >= expirationBlock
        )
    }

    private class RecognizedPersonInfo(val personId: PersonId, val personData: ProofOfInkPerson)
}
