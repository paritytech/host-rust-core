package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails

import androidx.lifecycle.SavedStateHandle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.disable
import io.paritytech.polkadotapp.common.utils.enable
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.mapResult
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.common.utils.withLoading
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooDetails
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.toTattooId
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.models.TattooCommitOutcome
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo.TattooDetailsInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooSizeUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.EvidenceReviewUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.TattooCommitmentUiState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.TattooDetailsUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.TattooMetadataUiModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

@HiltViewModel
class TattooDetailsViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val router: BecomeCitizenRouter,
    private val interactor: TattooDetailsInteractor,
    private val tattooImageLoader: TattooImageLoader
) : BaseViewModel(), TattooDetailsContract {
    private val payload: TattooDetailsPayload = savedStateHandle.getPayload()
    private val tattooId = payload.tattooId.toTattooId()

    override val details = flowOf {
        interactor.getTattooDetails(payload.familyId)
    }
        .mapResult { it.toUi() }
        .withLoading()
        .stateInBackground(initialValue = LoadingState.Loading)

    private val tattooCommitmentIsVisible = MutableStateFlow(false)
    private val tattooCommitmentInProgress = MutableStateFlow(false)

    override val commitmentState = combine(
        tattooCommitmentIsVisible,
        tattooCommitmentInProgress
    ) { isVisible, inProgress ->
        TattooCommitmentUiState(isVisible = isVisible, inProgress = inProgress)
    }
        .stateIn(this, SharingStarted.Eagerly, TattooCommitmentUiState())

    override fun onBackClicked() {
        router.back()
    }

    override fun onProceedWithThisTattooClicked() {
        tattooCommitmentIsVisible.enable()
    }

    override fun onTattooReservationDismissed() {
        tattooCommitmentIsVisible.disable()
    }

    override fun onConfirmTattooReservationClicked() {
        if (tattooCommitmentInProgress.value) return

        tattooCommitmentInProgress.enable()

        launch {
            interactor
                .commitToTattoo(tattooId)
                .onSuccess { outcome ->
                    when (outcome) {
                        TattooCommitOutcome.SUCCESS -> router.popTattooSelection()
                        TattooCommitOutcome.ALREADY_RESERVED -> showError("Already reserved")
                        TattooCommitOutcome.UNKNOWN -> showError("Unknown commitment outcome")
                    }
                }
                .onFailure { error ->
                    Timber.e(error)
                }

            tattooCommitmentInProgress.disable()
        }
    }

    private fun TattooDetails.toUi() = TattooDetailsUiModel(
        metadata = TattooMetadataUiModel(
            title = familyMetadata.name,
            description = familyMetadata.description,
            image = tattooImageLoader.getTattooImage(payload.tattooId.toTattooId(), payload.familyId)
        ),
        size = TattooSizeUiModel.fromMetadata(familyMetadata),
        evidenceReview = reviewTime?.let {
            EvidenceReviewUiModel(
                from = it.from,
                to = it.to
            )
        }
    )
}
