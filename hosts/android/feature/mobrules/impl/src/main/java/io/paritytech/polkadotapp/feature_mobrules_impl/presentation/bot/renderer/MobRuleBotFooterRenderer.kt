package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowDownward
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.design.utils.collectAsEffect
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatFooterRenderer
import io.paritytech.polkadotapp.feature_chats_api.presentation.common.getMaxMessageWidth
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.MobRuleBotFooterContract
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.MobRuleBotFooterViewModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose.MobRuleCaseCardWidget
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose.SuspendedMobRuleFooter
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.compose.VotingButtons
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleBotFooterUiState
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.VotingCaseUiModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.model.VotingOption
import io.paritytech.polkadotapp.common.R as RCommon

class MobRuleBotFooterRenderer : CustomChatFooterRenderer {
    @Composable
    override fun drawFooter() {
        val contract = hiltViewModel<MobRuleBotFooterViewModel>() as MobRuleBotFooterContract
        val state by contract.state.collectAsStateWithLifecycle()

        contract.votingFailedEvents.collectAsEffect { context, messageResId ->
            Toast.makeText(
                context,
                context.getString(messageResId),
                Toast.LENGTH_SHORT
            ).show()
        }

        when (val currentState = state) {
            is MobRuleBotFooterUiState.Suspended -> SuspendedMobRuleFooter(
                modifier = Modifier.padding(
                    horizontal = PolkadotTheme.spacings.mediumIncreased,
                    vertical = PolkadotTheme.spacings.large
                ),
                onReclaimClick = contract::onReclaimPeerStatusClick
            )

            is MobRuleBotFooterUiState.Active -> VotingFooterContent(
                state = currentState,
                onVoteClick = contract::onVoteClick,
                onOpenDetail = contract::openEvidenceDetail
            )
        }
    }
}

@Composable
private fun VotingFooterContent(
    state: MobRuleBotFooterUiState.Active,
    onVoteClick: (VotingCaseUiModel, VotingOption) -> Unit,
    onOpenDetail: (VotingCaseUiModel) -> Unit
) {
    val currentCase = state.currentCase
    when {
        currentCase != null -> {
            VotingCaseContent(
                currentCase = currentCase,
                isVotingAllowed = state.isVotingAllowed,
                onVoteClick = onVoteClick,
                onOpenDetail = onOpenDetail
            )

            if (state.pendingCasesCount > 0) {
                VerticalSpacer { small }
                PendingCasesLabel(pendingCasesCount = state.pendingCasesCount)
            }
        }

        state.showAllCasesCompleted -> AllCasesCompletedLabel()
    }
}

@Composable
private fun VotingCaseContent(
    currentCase: VotingCaseUiModel,
    isVotingAllowed: Boolean,
    onVoteClick: (VotingCaseUiModel, VotingOption) -> Unit,
    onOpenDetail: (VotingCaseUiModel) -> Unit
) {
    Column(
        modifier = Modifier
            .padding(start = PolkadotTheme.spacings.mediumIncreased)
            .widthIn(max = getMaxMessageWidth())
    ) {
        PolkadotSurface(
            shape = PolkadotTheme.shapes.mediumIncreased,
            color = PolkadotTheme.colors.bg.surface.nested
        ) {
            MobRuleCaseCardWidget(
                caseUiModel = currentCase,
                onVote = { vote -> onVoteClick(currentCase, vote) },
                onOpenDetail = { onOpenDetail(currentCase) },
                modifier = Modifier.padding(PolkadotTheme.spacings.extraTiny)
            )
        }

        if (isVotingAllowed) {
            VerticalSpacer { small }

            VotingButtons(
                onVote = { vote -> onVoteClick(currentCase, vote) }
            )
        } else {
            WatchPrompt()
        }
    }
}

@Composable
private fun WatchPrompt() {
    NovaText(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = PolkadotTheme.spacings.mediumIncreased,
                vertical = PolkadotTheme.spacings.extraMedium
            ),
        text = stringResource(RCommon.string.mob_rule_evidence_watch_prompt),
        style = PolkadotTheme.typography.body.medium,
        color = PolkadotTheme.colors.fg.secondary,
        textAlign = TextAlign.Start
    )
}

@Composable
private fun AllCasesCompletedLabel() {
    NovaText(
        modifier = Modifier
            .fillMaxWidth()
            .padding(PolkadotTheme.spacings.extraLarge),
        text = stringResource(RCommon.string.mob_rule_bot_all_cases_completed),
        style = PolkadotTheme.typography.body.medium,
        color = PolkadotTheme.colors.fg.secondary,
        textAlign = TextAlign.Center
    )
}

@Composable
private fun PendingCasesLabel(pendingCasesCount: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0x14FFFFFF))
            .padding(PolkadotTheme.spacings.small)
    ) {
        NovaText(
            text = stringResource(RCommon.string.mob_rule_bot_judge_to_unlock, pendingCasesCount),
            style = PolkadotTheme.typography.body.mediumEmphasized,
            color = PolkadotTheme.colors.fg.primary
        )

        HorizontalSpacer { small }

        NovaIcon(
            imageVector = NovaIcons.ArrowDownward,
            tint = PolkadotTheme.colors.fg.primary,
            modifier = Modifier.size(16.dp)
        )
    }
}
