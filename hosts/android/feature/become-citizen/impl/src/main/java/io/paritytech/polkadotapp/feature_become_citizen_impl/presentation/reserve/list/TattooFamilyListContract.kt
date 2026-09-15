package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list

import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.CandidateApplicableUiState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.models.TattooFamilyUiModel
import kotlinx.coroutines.flow.StateFlow

interface TattooFamilyListContract {
    val candidateApplicable: StateFlow<LoadingState<CandidateApplicableUiState>>
    val tattooFamilies: StateFlow<LoadingState<List<TattooFamilyUiModel>>>
    val applyInProgress: StateFlow<Boolean>
    val depositInProgress: StateFlow<Boolean>

    fun depositClicked()
    fun selectFamily(family: TattooFamilyUiModel)

    fun onBackClick()
    fun applyClick()
}
