@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.design.components.progress.LoadingScreenState
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.CandidateApplicableUiState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.TattooFamilyListContract
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components.CanApplyFooter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components.NotEnoughDepositFooter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.components.TattooFamiliesContent
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.models.TattooFamilyUiModel

@Composable
fun TattooFamilyListScreen(contract: TattooFamilyListContract) {
    val candidateApplicableState = contract.candidateApplicable.collectAsState().value
    val tattooFamiliesState = contract.tattooFamilies.collectAsState().value
    val applyInProgress = contract.applyInProgress.collectAsState().value
    val depositInProgress = contract.depositInProgress.collectAsState().value

    TattooFamilyListScreenInternal(
        candidateApplicableState = candidateApplicableState,
        tattooFamiliesState = tattooFamiliesState,
        onSelectFamily = contract::selectFamily,
        onBackAction = contract::onBackClick,
        onDeposit = contract::depositClicked,
        onApply = contract::applyClick,
        applyInProgress = applyInProgress,
        depositInProgress = depositInProgress,
    )
}

@Composable
private fun TattooFamilyListScreenInternal(
    candidateApplicableState: LoadingState<CandidateApplicableUiState>,
    tattooFamiliesState: LoadingState<List<TattooFamilyUiModel>>,
    onSelectFamily: (TattooFamilyUiModel) -> Unit,
    onBackAction: () -> Unit,
    onDeposit: () -> Unit,
    onApply: () -> Unit,
    applyInProgress: Boolean,
    depositInProgress: Boolean
) {
    PolkadotSurface {
        when (candidateApplicableState) {
            is LoadingState.Loading -> LoadingScreenState()
            is LoadingState.Error -> Unit
            is LoadingState.Loaded -> {
                TattooFamiliesContent(
                    isApplied = candidateApplicableState.data is CandidateApplicableUiState.Applied,
                    familiesState = tattooFamiliesState,
                    onFamilyAction = onSelectFamily,
                    onBackAction = onBackAction,
                    footer = {
                        when (val state = candidateApplicableState.data) {
                            is CandidateApplicableUiState.CanApply -> {
                                CanApplyFooter(
                                    currentBalance = state.requiredAmount,
                                    onApply = onApply,
                                    applyInProgress = applyInProgress
                                )
                            }

                            is CandidateApplicableUiState.NotEnoughBalance -> {
                                NotEnoughDepositFooter(
                                    depositInProgress = depositInProgress,
                                    requiredDeposit = state.requiredAmount,
                                    assetDisplay = state.assetDisplay,
                                    onDepositAction = onDeposit
                                )
                            }

                            is CandidateApplicableUiState.Applied,
                            CandidateApplicableUiState.Unexpected -> Unit
                        }
                    }
                )
            }
        }
    }
}
