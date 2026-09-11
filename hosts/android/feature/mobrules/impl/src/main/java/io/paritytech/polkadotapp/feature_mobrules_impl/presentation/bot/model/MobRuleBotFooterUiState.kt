package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model

import androidx.compose.runtime.Immutable

sealed interface MobRuleBotFooterUiState {
    data object Suspended : MobRuleBotFooterUiState

    @Immutable
    data class Active(
        val currentCase: VotingCaseUiModel? = null,
        val pendingCasesCount: Int = 0,
        val showAllCasesCompleted: Boolean = false,
        val isVotingAllowed: Boolean = true
    ) : MobRuleBotFooterUiState
}
