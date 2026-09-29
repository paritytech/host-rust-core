package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails

import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.TattooCommitmentUiState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models.TattooDetailsUiModel
import kotlinx.coroutines.flow.StateFlow

interface TattooDetailsContract {
    val details: StateFlow<LoadingState<TattooDetailsUiModel>>
    val commitmentState: StateFlow<TattooCommitmentUiState>

    fun onBackClicked()
    fun onProceedWithThisTattooClicked()
    fun onTattooReservationDismissed()
    fun onConfirmTattooReservationClicked()
}
