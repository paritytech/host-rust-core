package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.combineToPair
import io.paritytech.polkadotapp.common.utils.filterResultSuccessNotNull
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.wrapIntoResult
import io.paritytech.polkadotapp.feature_become_citizen_api.data.updaters.BecomeCitizenUpdateSystem
import io.paritytech.polkadotapp.feature_become_citizen_api.data.upload.EvidenceUploadStarter
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.dim.Dim1CommitmentHandler
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.EvidenceLocalState
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimState
import io.paritytech.polkadotapp.feature_people_api.domain.dim.GetActiveDimCommitmentState
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeToFullUsernameState
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.ReadyToUpgradeUsernameUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.transformLatest
import javax.inject.Inject

interface TattooBotInteractor {
    fun startUpdateSystems(): Flow<*>

    context(scope: ComputationalScope)
    fun subscribeToBotState(): Flow<TattooBotState>

    context(scope: ComputationalScope)
    suspend fun observeBotStepAndStartEvidenceUploader()

    fun subscribeReadyToUpgradeUsername(): Flow<UpgradeToFullUsernameState>
}

class RealTattooBotInteractor @Inject constructor(
    private val becomeCitizenUpdateSystem: BecomeCitizenUpdateSystem,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase,
    private val getActiveDimCommitmentState: GetActiveDimCommitmentState,
    private val evidenceLocalStateStorage: EvidenceLocalStateStorage,
    private val evidenceStorage: EvidenceStorage,
    private val evidenceUploadStarter: EvidenceUploadStarter,
    private val readyToUpgradeUsernameUseCase: ReadyToUpgradeUsernameUseCase,
    private val personStatusUseCase: PersonStatusUseCase
) : TattooBotInteractor {
    override fun startUpdateSystems(): Flow<*> {
        return merge(
            becomeCitizenUpdateSystem.peopleUpdateSystem.start(),
            becomeCitizenUpdateSystem.bulletInUpdateSystem.start()
        ).wrapIntoResult()
            .logFailure("Unexpected failure when starting tattoo bot update system")
    }

    context(scope: ComputationalScope)
    override fun subscribeToBotState(): Flow<TattooBotState> = getActiveDimCommitmentState(Dim1CommitmentHandler.DIM_ID)
        .transformLatest { dimState ->
            when (dimState) {
                is DimState.Started -> {
                    val state = if (dimState.cancellable) {
                        TattooBotState.OTHER_DIM_COMMITMENT
                    } else {
                        TattooBotState.OTHER_DIM_IN_PROGRESS
                    }

                    emit(state)
                }

                DimState.NotStarted, null -> {
                    emitAll(createTattooProgressBotState())
                }
            }
        }.distinctUntilChanged()

    private fun createTattooProgressBotState() = combineToPair(
        tattooProgressStateUseCase.tattooProgressStateFlow().filterResultSuccessNotNull(),
        personStatusUseCase.personhoodAccountsFullySetFlow(),
    ).transformLatest { (tattooProgressState, isPerson) ->
        when (tattooProgressState) {
            is TattooProgressState.NotStarted,
            is TattooProgressState.Applied -> emit(TattooBotState.TATTOO_SELECTION)

            is TattooProgressState.Committed -> emitAll(createEvidencesStateFlow())
            is TattooProgressState.UploadingEvidence,
            is TattooProgressState.RegisteringPerson -> emit(TattooBotState.WAITING_FOR_CONFIRMATION)
            is TattooProgressState.RecognizedPerson -> emit(if (isPerson) TattooBotState.REGISTERED_PERSON else TattooBotState.EVIDENCES_CONFIRMED)
            is TattooProgressState.UnrecoverableFailure -> emit(TattooBotState.UNRECOVERABLE_ERROR)
            is TattooProgressState.Unknown -> error("Unknown tattoo progress state")
        }
    }.distinctUntilChanged()

    context(scope: ComputationalScope)
    override suspend fun observeBotStepAndStartEvidenceUploader() {
        val step = subscribeToBotState()
            .first { it == TattooBotState.EVIDENCES_CONFIRMED || it == TattooBotState.WAITING_FOR_CONFIRMATION }

        if (step == TattooBotState.WAITING_FOR_CONFIRMATION) {
            evidenceUploadStarter.startUpload()
        }
    }

    override fun subscribeReadyToUpgradeUsername() = readyToUpgradeUsernameUseCase()

    private fun createEvidencesStateFlow(): Flow<TattooBotState> =
        combine(
            evidenceLocalStateStorage.subscribeState(EvidenceType.VIDEO),
            evidenceLocalStateStorage.subscribeState(EvidenceType.PHOTO)
        ) { videoEvidenceState, photoEvidenceState ->
            val isVideoStored = evidenceStorage.isEvidenceStored(EvidenceType.VIDEO)
            val isPhotoStored = evidenceStorage.isEvidenceStored(EvidenceType.PHOTO)

            val isVideoConfirmed = videoEvidenceState == EvidenceLocalState.CONFIRMED && isVideoStored
            val isPhotoConfirmed = photoEvidenceState == EvidenceLocalState.CONFIRMED && isPhotoStored

            when {
                !isVideoConfirmed -> TattooBotState.WAITING_FOR_VIDEO_EVIDENCE
                !isPhotoConfirmed -> TattooBotState.WAITING_FOR_PHOTO_EVIDENCE
                else -> TattooBotState.WAITING_FOR_CONFIRMATION
            }
        }
}
