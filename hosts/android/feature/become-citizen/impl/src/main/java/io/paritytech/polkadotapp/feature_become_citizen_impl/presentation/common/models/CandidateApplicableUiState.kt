package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models

import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.AssetDisplay
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel

sealed interface CandidateApplicableUiState {
    data class NotEnoughBalance(
        val requiredAmount: TokenAmountModel,
        val assetDisplay: AssetDisplay
    ) : CandidateApplicableUiState

    data class CanApply(
        val requiredAmount: TokenAmountModel,
    ) : CandidateApplicableUiState

    data object Applied : CandidateApplicableUiState
    data object Unexpected : CandidateApplicableUiState
}
