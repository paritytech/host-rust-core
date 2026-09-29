package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Clock
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDrawingContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.LastMessageUiModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseJudgmentStatus
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleCaseStatusContent
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

private val CLOCK_ICON_SIZE = 16.dp

class MobRuleCaseStatusMessageRenderer @Inject constructor(
    @param:ApplicationContext private val appContext: Context
) : CustomChatMessageRenderer<MobRuleCaseStatusContent> {
    companion object {
        const val ID = "MobRuleCaseStatusMessageRenderer"
    }

    override val id: String = ID

    override val contentSerializer = MobRuleCaseStatusContent.serializer()

    @Composable
    override fun DrawMessage(
        message: ChatMessageUiModel.Custom<MobRuleCaseStatusContent>,
        context: MessageDrawingContext
    ) {
        message.content.onSuccess { content ->
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = PolkadotTheme.spacings.small, bottom = PolkadotTheme.spacings.mediumIncreased),
                contentAlignment = Alignment.Center
            ) {
                when (content.status) {
                    CaseJudgmentStatus.PROCESSING -> ProcessingStatus()
                    CaseJudgmentStatus.CORRECT -> CorrectStatus()
                    CaseJudgmentStatus.INCORRECT -> IncorrectStatus()
                }
            }
        }
    }

    override suspend fun formatNotificationContent(message: ChatMessage.Content.Custom<MobRuleCaseStatusContent>): Result<String> {
        return message.content.map { content ->
            when (content.status) {
                CaseJudgmentStatus.PROCESSING -> appContext.getString(RCommon.string.mob_rule_judgment_processing)
                CaseJudgmentStatus.CORRECT -> appContext.getString(RCommon.string.mob_rule_judgment_correct)
                CaseJudgmentStatus.INCORRECT -> appContext.getString(RCommon.string.mob_rule_judgment_incorrect)
            }
        }
    }

    @Composable
    override fun formatChatPreview(message: LastMessageUiModel.Custom<MobRuleCaseStatusContent>): Result<String> {
        return message.content.map { content ->
            when (content.status) {
                CaseJudgmentStatus.PROCESSING -> stringResource(RCommon.string.mob_rule_judgment_processing)
                CaseJudgmentStatus.CORRECT -> stringResource(RCommon.string.mob_rule_judgment_correct)
                CaseJudgmentStatus.INCORRECT -> stringResource(RCommon.string.mob_rule_judgment_incorrect)
            }
        }
    }
}

@Composable
private fun ProcessingStatus() {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.tiny)
    ) {
        NovaText(
            text = stringResource(RCommon.string.mob_rule_judgment_processing),
            style = PolkadotTheme.typography.body.medium,
            color = PolkadotTheme.colors.fg.secondary
        )

        NovaIcon(
            modifier = Modifier.size(CLOCK_ICON_SIZE),
            imageVector = NovaIcons.Clock,
            tint = PolkadotTheme.colors.fg.secondary
        )
    }
}

@Composable
private fun CorrectStatus() {
    NovaText(
        text = stringResource(RCommon.string.mob_rule_judgment_correct),
        style = PolkadotTheme.typography.body.medium,
        color = PolkadotTheme.colors.fg.secondary
    )
}

@Composable
private fun IncorrectStatus() {
    NovaText(
        text = stringResource(RCommon.string.mob_rule_judgment_incorrect),
        style = PolkadotTheme.typography.body.medium,
        color = PolkadotTheme.colors.fg.secondary
    )
}
