package io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.BuildConfig
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBot
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMetadata
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatFooterRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatConfig
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatExtensionId
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.compose.FaqQuestions
import io.paritytech.polkadotapp.feature_chats_impl.domain.middleware.bot.polkadotpeer.PolkadotPeerBotInitialMessageProvider
import io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot.compose.PolkadotPeerBotFooter
import io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot.models.PolkadotChatPeerBotQuestion
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
internal class PolkadotPeerBot @Inject constructor(
    private val initialMessageProvider: PolkadotPeerBotInitialMessageProvider,
) : ChatBot() {
    private val chatData = ChatBotData.polkadotPeer()

    override val id: ChatExtensionId = chatData.id
    override val metadata = ChatBotMetadata(chatData.name, icon = null)

    override val customFooterRenderer: CustomChatFooterRenderer = PolkadotPeerCustomFooterRenderer()

    context(chatBotContext: ChatBotContext)
    override fun startBotWork() {
        chatBotContext.scope.launch {
            chatBotContext.setWelcomeMessages { initialMessageProvider.getMessages() }
        }
    }

    override fun observeUserInputAllowed(): Flow<Boolean> = flowOf(false)

    override fun observeChatConfig() = flowOf(
        ChatConfig(
            showTimestamps = false,
            showAvatar = false,
            showNewMessagesSeparator = true,
        )
    )

    private inner class PolkadotPeerCustomFooterRenderer : CustomChatFooterRenderer {
        @Composable
        override fun drawFooter() {
            val contract = hiltViewModel<PolkadotPeerBotViewModel>() as PolkadotPeerBotContract
            val state by contract.state.collectAsStateWithLifecycle()

            Column {
                if (BuildConfig.FAQ_ENABLED) {
                    FaqQuestions(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = PolkadotTheme.spacings.mediumIncreased),
                        botId = id,
                        allQuestions = PolkadotChatPeerBotQuestion.entries.toImmutableList()
                    )

                    VerticalSpacer { mediumIncreased }
                }

                PolkadotPeerBotFooter(
                    state = state,
                    onNavigationToDim1Click = contract::openTattooBot,
                    onNavigationToDim2Click = contract::openWeeklyGameBot
                )
            }
        }
    }
}
