package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails

import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.models.TattooFamilyDetailsPreviewUiModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.models.TattooFamilyDetailsUiModel
import kotlinx.coroutines.flow.StateFlow

interface TattooFamilyDetailsContract {
    val familyDetails: StateFlow<LoadingState<TattooFamilyDetailsUiModel>>

    fun onPreviewClick(preview: TattooFamilyDetailsPreviewUiModel)

    fun onBackClick()
}
