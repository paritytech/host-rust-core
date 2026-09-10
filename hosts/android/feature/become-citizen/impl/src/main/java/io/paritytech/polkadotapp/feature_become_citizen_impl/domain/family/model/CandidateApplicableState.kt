package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.model

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount

sealed interface CandidateApplicableState {
    data class NotEnoughBalance(val requiredAmount: ChainAssetWithAmount) : CandidateApplicableState
    data class CanApply(val currentAmount: ChainAssetWithAmount) : CandidateApplicableState
    data object Applied : CandidateApplicableState
    data object Unexpected : CandidateApplicableState
}
