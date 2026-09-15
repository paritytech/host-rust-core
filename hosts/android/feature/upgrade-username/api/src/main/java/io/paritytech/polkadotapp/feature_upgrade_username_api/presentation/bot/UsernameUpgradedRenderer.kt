package io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDrawingContext
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatMessageUiModel
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.LastMessageUiModel
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UsernameUpgradedContent
import javax.inject.Inject

class UsernameUpgradedRenderer @Inject constructor(
    @param:ApplicationContext private val appContext: Context
) : CustomChatMessageRenderer<UsernameUpgradedContent> {
    companion object {
        const val ID = "UsernameUpgradedRenderer"
    }

    override val id: String = ID

    override val contentSerializer = UsernameUpgradedContent.serializer()

    @Composable
    override fun DrawMessage(
        message: ChatMessageUiModel.Custom<UsernameUpgradedContent>,
        context: MessageDrawingContext
    ) {
        message.content.onSuccess { content ->
            UpgradeUsernameWidget(
                modifier = Modifier.padding(
                    horizontal = PolkadotTheme.spacings.mediumIncreased,
                    vertical = PolkadotTheme.spacings.small
                ),
                usernameWithoutSuffix = content.usernameWithoutSuffix,
                isUpgraded = true
            )
        }
    }

    override suspend fun formatNotificationContent(message: ChatMessage.Content.Custom<UsernameUpgradedContent>) = message.content.map {
        appContext.getString(R.string.upgrade_username_upgraded_placeholder, it.username, it.usernameWithoutSuffix)
    }

    @Composable
    override fun formatChatPreview(message: LastMessageUiModel.Custom<UsernameUpgradedContent>) = message.content.map {
        stringResource(R.string.upgrade_username_upgraded_placeholder, it.username, it.usernameWithoutSuffix)
    }
}
