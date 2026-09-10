package io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot

import io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot.models.PolkadotPeerBotFooterState
import kotlinx.coroutines.flow.StateFlow

interface PolkadotPeerBotContract {
    val state: StateFlow<PolkadotPeerBotFooterState>

    fun openWeeklyGameBot()

    fun openTattooBot()
}
