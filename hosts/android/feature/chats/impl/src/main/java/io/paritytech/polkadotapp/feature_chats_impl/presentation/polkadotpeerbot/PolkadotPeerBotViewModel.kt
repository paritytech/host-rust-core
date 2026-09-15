package io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.BuildConfig
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotStateController
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_chats_impl.ChatsRouter
import io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot.models.PolkadotPeerBotFooterState
import kotlinx.coroutines.flow.MutableStateFlow
import javax.inject.Inject

@HiltViewModel
class PolkadotPeerBotViewModel @Inject constructor(
    private val chatBotStateController: ChatBotStateController,
    private val chatsRouter: ChatsRouter,
) : BaseViewModel(), PolkadotPeerBotContract {
    override val state = MutableStateFlow(
        PolkadotPeerBotFooterState(showDim1NavigationButton = BuildConfig.DIM1_ENABLED, showDim2NavigationButton = true)
    )

    override fun openWeeklyGameBot() = launchUnit { openBot(ChatBotData.weeklyGame()) }

    override fun openTattooBot() = launchUnit { openBot(ChatBotData.tattoo()) }

    private suspend fun openBot(chatBotData: ChatBotData) {
        chatBotStateController.setActive(chatBotData.id)

        chatsRouter.back()
        chatsRouter.openChatFeed(ChatFeedPayload.botChat(chatBotData.id))
    }
}
