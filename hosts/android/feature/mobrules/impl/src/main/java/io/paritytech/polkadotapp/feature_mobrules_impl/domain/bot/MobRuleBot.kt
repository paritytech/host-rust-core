package io.paritytech.polkadotapp.feature_mobrules_impl.domain.bot

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBot
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotMetadata
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotStateController
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatMessageRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatConfig
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatExtensionId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.createAttachmentFromDrawable
import io.paritytech.polkadotapp.feature_mobrules_impl.R
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer.MobRuleBotFooterRenderer
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer.MobRuleCaseStatusMessageRenderer
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.renderer.MobRuleVotedCaseMessageRenderer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class MobRuleBot @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val botStateController: ChatBotStateController,
    private val votedCaseRenderer: MobRuleVotedCaseMessageRenderer,
    private val caseStatusRenderer: MobRuleCaseStatusMessageRenderer,
    private val voteMessageProcessor: MobRuleVoteMessageProcessor,
    private val caseStatusMessageProcessor: MobRuleCaseStatusMessageProcessor,
) : ChatBot() {
    private val data = ChatBotData.mobRule()

    override val id: ChatExtensionId = data.id
    override val metadata = ChatBotMetadata(data.name, icon = null)

    override val customFooterRenderer = MobRuleBotFooterRenderer()

    override fun customMessageRenderers(): List<CustomChatMessageRenderer<*>> {
        return listOf(votedCaseRenderer, caseStatusRenderer)
    }

    context(chatBotContext: ChatBotContext)
    override fun startBotWork() {
        chatBotContext.scope.launch {
            botStateController.awaitActive(id)

            chatBotContext.setWelcomeMessages { createWelcomeMessages() }

            voteMessageProcessor.launchSendingMessages()
            caseStatusMessageProcessor.launchSendingMessages()
        }
    }

    override fun observeUserInputAllowed(): Flow<Boolean> = flowOf(false)

    override fun observeChatConfig() = flowOf(
        ChatConfig(
            showAvatar = false,
            showTimestamps = true,
            showNewMessagesSeparator = true,
        )
    )

    private fun createWelcomeMessages(): List<ChatMessage.Content> = listOf(
        ChatMessage.Content.RichText(
            text = context.getString(RCommon.string.mob_rule_bot_welcome),
            attachments = listOf(context.createAttachmentFromDrawable(R.drawable.chat_bot_mob_rule_welcome))
        )
    )
}
