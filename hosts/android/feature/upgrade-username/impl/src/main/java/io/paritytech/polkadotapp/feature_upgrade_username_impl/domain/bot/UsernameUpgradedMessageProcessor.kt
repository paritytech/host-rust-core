package io.paritytech.polkadotapp.feature_upgrade_username_impl.domain.bot

import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotContext
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.messageWasSent
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.bot.UsernameUpgradedMessageProcessor
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UpgradeToFullUsernameState
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.model.UsernameUpgradedContent
import io.paritytech.polkadotapp.feature_upgrade_username_api.domain.usecase.ReadyToUpgradeUsernameUseCase
import io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot.UsernameUpgradedRenderer
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

class RealUsernameUpgradedMessageProcessor @Inject constructor(
    private val readyToUpgradeUsernameUseCase: ReadyToUpgradeUsernameUseCase
) : UsernameUpgradedMessageProcessor {
    context(chatBotContext: ChatBotContext)
    override fun launchSendingMessages() {
        chatBotContext.scope.launch {
            val completedState = awaitUsernameUpgraded()
            if (messageWasSent<UsernameUpgradedContent>()) return@launch

            sendUsernameUpgradedMessage(completedState)
        }
    }

    private suspend fun awaitUsernameUpgraded() = readyToUpgradeUsernameUseCase()
        .filter { it is UpgradeToFullUsernameState.Completed }
        .first() as UpgradeToFullUsernameState.Completed

    context(chatBotContext: ChatBotContext)
    private suspend fun sendUsernameUpgradedMessage(usernameState: UpgradeToFullUsernameState.Completed) {
        val customContent = UsernameUpgradedContent(
            username = usernameState.liteUsername.getDisplayUsername(),
            usernameWithoutSuffix = usernameState.fullUsername.getDisplayUsername()
        )

        chatBotContext.sendCustomMessage(
            rendererId = UsernameUpgradedRenderer.ID,
            content = customContent,
        )
    }
}
