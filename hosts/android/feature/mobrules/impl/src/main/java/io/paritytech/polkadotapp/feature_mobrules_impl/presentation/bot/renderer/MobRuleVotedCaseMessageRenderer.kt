package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButtonSize
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.components.spacer.HorizontalSpacer
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.toDomain
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDrawingContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.LastMessageUiModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.MobRuleBotFooterContract
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.MobRuleBotFooterViewModel
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.CaseType
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model.MobRuleVotedCaseContent
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsImageRequest
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class MobRuleVotedCaseMessageRenderer @Inject constructor(
    @param:ApplicationContext private val appContext: Context,
    private val tattooImageLoader: TattooImageLoader
) : CustomChatMessageRenderer<MobRuleVotedCaseContent> {
    companion object {
        const val ID = "MobRuleVotedCaseMessageRenderer"
    }

    override val id: String = ID

    override val contentSerializer = MobRuleVotedCaseContent.serializer()

    @Composable
    override fun DrawMessage(
        message: ChatMessageUiModel.Custom<MobRuleVotedCaseContent>,
        context: MessageDrawingContext
    ) {
        val contract = hiltViewModel<MobRuleBotFooterViewModel>() as MobRuleBotFooterContract

        message.content.onSuccess { content ->
            val tattooImage = resolveTattooImage(content)

            Column(
                modifier = context.messageModifier
                    .fillMaxWidth()
                    .clip(PolkadotTheme.shapes.mediumIncreased)
                    .background(PolkadotTheme.colors.bg.surface.nested)
                    .padding(PolkadotTheme.spacings.extraMedium)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OverlappingThumbnails(
                        evidenceHashHex = content.evidenceHashHex,
                        tattooImage = tattooImage
                    )

                    HorizontalSpacer { small }

                    NovaText(
                        text = content.caseType.title,
                        style = PolkadotTheme.typography.title.medium,
                        color = PolkadotTheme.colors.fg.primary
                    )
                }

                VerticalSpacer { extraMedium }

                HorizontalDivider(color = Color(0x1FFFFFFF))

                VerticalSpacer { extraMedium }

                PolkadotTextButton(
                    text = stringResource(RCommon.string.mob_rule_view_case),
                    style = PolkadotButtonStyle.secondary(),
                    size = PolkadotButtonSize.large(),
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { contract.openVotedCaseDetail(content) }
                )
            }
        }
    }

    override suspend fun formatNotificationContent(message: ChatMessage.Content.Custom<MobRuleVotedCaseContent>) =
        message.content.map { content ->
            content.caseType.title
        }

    @Composable
    override fun formatChatPreview(message: LastMessageUiModel.Custom<MobRuleVotedCaseContent>) =
        message.content.map { content ->
            content.caseType.title
        }

    private fun resolveTattooImage(content: MobRuleVotedCaseContent): TattooImage {
        return tattooImageLoader.getTattooImage(
            content.tattooId.toDomain(),
            content.tattooFamilyIdHex.fromHex()
        )
    }

    private val CaseType.title: String
        get() = when (this) {
            CaseType.PHOTO -> appContext.getString(RCommon.string.mob_rule_bot_photo_title)
            CaseType.VIDEO -> appContext.getString(RCommon.string.mob_rule_bot_video_title)
        }
}

private val OverlapOffset = (-4).dp

@Composable
private fun OverlappingThumbnails(
    evidenceHashHex: String?,
    tattooImage: TattooImage
) {
    Row {
        evidenceHashHex?.let { hashHex ->
            NovaAsyncImage(
                model = IpfsImageRequest(hashHex.fromHex()),
                modifier = Modifier
                    .size(16.dp)
                    .zIndex(1f)
                    .border(PolkadotTheme.borders.default, PolkadotTheme.colors.bg.surface.nested, PolkadotTheme.shapes.tiny)
                    .clip(PolkadotTheme.shapes.tiny)
            )
        }

        NovaAsyncImage(
            model = tattooImage.loadable,
            modifier = Modifier
                .size(16.dp)
                .offset(x = OverlapOffset)
                .clip(PolkadotTheme.shapes.tiny)
        )
    }
}
