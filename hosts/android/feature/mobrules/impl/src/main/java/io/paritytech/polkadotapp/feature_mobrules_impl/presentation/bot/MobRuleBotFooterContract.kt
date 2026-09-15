package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot

import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleBotFooterUiState
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleVotedCaseContent
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.VotingCaseUiModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface MobRuleBotFooterContract {
    val state: StateFlow<MobRuleBotFooterUiState>

    val votingFailedEvents: Flow<Int>

    fun onVoteClick(case: VotingCaseUiModel, vote: VotingOption)

    fun openEvidenceDetail(case: VotingCaseUiModel)

    fun openVotedCaseDetail(content: MobRuleVotedCaseContent)

    fun onReclaimPeerStatusClick()
}
