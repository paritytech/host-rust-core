@file:OptIn(ExperimentalMaterial3Api::class)

package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot

import android.content.Context
import androidx.compose.material3.ExperimentalMaterial3Api
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_become_citizen_impl.R
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.TattooBotInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.bot.TattooProgressMessageProcessor
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.footer.TattooBotFooterRenderer
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.SelectedTattooRenderer
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.EvidenceProvidedMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBot
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMetadata
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatFooterRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatConfig
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatExtensionId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.createAttachmentFromDrawable
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.bot.UsernameUpgradedMessageProcessor
import io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot.UsernameUpgradedRenderer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class TattooBot @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val usernameUpgradedRenderer: UsernameUpgradedRenderer,
    private val selectedTattooRenderer: SelectedTattooRenderer,
    private val evidenceProvidedMessageRenderer: EvidenceProvidedMessageRenderer,
    private val interactor: TattooBotInteractor,
    private val usernameUpgradedMessageProcessor: UsernameUpgradedMessageProcessor,
    private val tattooProgressMessageProcessor: TattooProgressMessageProcessor
) : ChatBot() {
    private val data = ChatBotData.tattoo()

    override val id: ChatExtensionId = data.id
    override val metadata = ChatBotMetadata(data.name, icon = null)

    override val customFooterRenderer: CustomChatFooterRenderer = TattooBotFooterRenderer()

    override fun customMessageRenderers(): List<CustomChatMessageRenderer<*>> {
        return listOf(usernameUpgradedRenderer, selectedTattooRenderer, evidenceProvidedMessageRenderer)
    }

    context(chatBotContext: ChatBotContext)
    override fun startBotWork() {
        interactor.startUpdateSystems().launchIn(chatBotContext.scope)

        chatBotContext.scope.launch {
            chatBotContext.setWelcomeMessages { createWelcomeMessages() }

            usernameUpgradedMessageProcessor.launchSendingMessages()
            tattooProgressMessageProcessor.launchSendingMessages()
        }
    }

    override fun observeUserInputAllowed(): Flow<Boolean> = flowOf(false)

    override fun observeChatConfig() = flowOf(
        ChatConfig(
            showAvatar = false,
            showTimestamps = false,
            showNewMessagesSeparator = true,
        )
    )

    private fun createWelcomeMessages(): List<ChatMessage.Content> = listOf(
        ChatMessage.Content.Text(
            text = context.getString(RCommon.string.chat_bot_tattoo_welcome_message_1)
        ),
        ChatMessage.Content.RichText(
            text = context.getString(RCommon.string.chat_bot_tattoo_welcome_message_2),
            attachments = listOf(context.createAttachmentFromDrawable(R.drawable.chat_bot_tattoo_placement))
        ),
        ChatMessage.Content.RichText(
            text = context.getString(RCommon.string.chat_bot_tattoo_welcome_message_3),
            attachments = listOf(context.createAttachmentFromDrawable(R.drawable.chat_bot_tattoo_unique_design))
        ),
        ChatMessage.Content.Text(
            text = context.getString(RCommon.string.chat_bot_tattoo_welcome_message_4)
        ),
        ChatMessage.Content.RichText(
            text = context.getString(RCommon.string.chat_bot_tattoo_welcome_message_5),
            attachments = listOf(context.createAttachmentFromDrawable(R.drawable.chat_bot_tattoo_evidence))
        ),
        ChatMessage.Content.Text(
            text = context.getString(RCommon.string.chat_bot_tattoo_welcome_message_6)
        )
    )
}
