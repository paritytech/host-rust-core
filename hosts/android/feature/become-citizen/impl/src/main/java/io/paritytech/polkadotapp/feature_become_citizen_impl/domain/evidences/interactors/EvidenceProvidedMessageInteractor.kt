package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors

import android.net.Uri
import androidx.core.net.toUri
import io.paritytech.polkadotapp.common.utils.Fraction.Companion.percents
import io.paritytech.polkadotapp.common.utils.filterResultSuccessNotNull
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState.UploadingEvidence.Status
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState.TattooProgressStateUseCase
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.EvidenceLocalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.models.EvidenceProvidingState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import javax.inject.Inject

class EvidenceProvidedMessageInteractor @Inject constructor(
    private val evidenceStorage: EvidenceStorage,
    private val evidenceLocalStateStorage: EvidenceLocalStateStorage,
    private val tattooProgressStateUseCase: TattooProgressStateUseCase
) {
    fun subscribeEvidenceUri(evidenceType: EvidenceType): Flow<Uri?> = evidenceLocalStateStorage
        .subscribeState(evidenceType)
        .map {
            when (it) {
                EvidenceLocalState.NOT_PRESENT -> null
                EvidenceLocalState.PRESENT,
                EvidenceLocalState.CONFIRMED -> {
                    if (evidenceStorage.isEvidenceStored(evidenceType)) {
                        evidenceStorage.getEvidenceFile(evidenceType).toUri()
                    } else {
                        null
                    }
                }
            }
        }

    fun subscribeEvidenceProvidingState(evidenceType: EvidenceType): Flow<EvidenceProvidingState> =
        tattooProgressStateUseCase.tattooProgressStateFlow()
            .filterResultSuccessNotNull()
            .map { progressState ->
                when (progressState) {
                    is TattooProgressState.NotStarted,
                    is TattooProgressState.Applied,
                    is TattooProgressState.Committed -> EvidenceProvidingState.Queued

                    is TattooProgressState.UploadingEvidence -> {
                        when (progressState.evidenceType) {
                            EvidenceType.PHOTO -> createPhotoEvidenceState(evidenceType, progressState)
                            EvidenceType.VIDEO -> createVideoEvidenceState(evidenceType, progressState)
                        }
                    }

                    is TattooProgressState.UnrecoverableFailure -> EvidenceProvidingState.Failed

                    is TattooProgressState.RegisteringPerson,
                    is TattooProgressState.RecognizedPerson -> EvidenceProvidingState.Approved

                    is TattooProgressState.Unknown -> error("Unexpected TattooProgressState.Unknown")
                }
            }
            .distinctUntilChanged()

    private fun createVideoEvidenceState(
        subscribedEvidenceType: EvidenceType,
        progressState: TattooProgressState.UploadingEvidence
    ): EvidenceProvidingState = when (subscribedEvidenceType) {
        EvidenceType.PHOTO -> EvidenceProvidingState.Approved // if video is uploading, photo is already approved or not required
        EvidenceType.VIDEO -> progressState.toEvidenceProvidingState()
    }

    private fun createPhotoEvidenceState(
        subscribedEvidenceType: EvidenceType,
        progressState: TattooProgressState.UploadingEvidence
    ): EvidenceProvidingState = when (subscribedEvidenceType) {
        EvidenceType.PHOTO -> progressState.toEvidenceProvidingState()
        EvidenceType.VIDEO -> EvidenceProvidingState.Queued // when photo is uploading, video is in queue
    }

    private fun TattooProgressState.UploadingEvidence.toEvidenceProvidingState(): EvidenceProvidingState =
        when (val status = status) {
            is Status.WaitingForStorageAllocation -> EvidenceProvidingState.Queued
            is Status.UploadingInProgress -> EvidenceProvidingState.Uploading(status.progress)
            is Status.FinalizingUploading -> EvidenceProvidingState.Uploading(100.percents)
            is Status.WaitingForJudgement -> EvidenceProvidingState.InReview
        }
}
