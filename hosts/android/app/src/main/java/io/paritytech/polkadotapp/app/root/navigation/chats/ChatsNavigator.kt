package io.paritytech.polkadotapp.app.root.navigation.chats

import io.paritytech.polkadotapp.app.R
import io.paritytech.polkadotapp.app.root.navigation.BaseNavigator
import io.paritytech.polkadotapp.app.root.navigation.NavigationHolder
import io.paritytech.polkadotapp.common.utils.toPayloadBundle
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_chats_impl.ChatsRouter
import io.paritytech.polkadotapp.feature_wallet_api.presentation.enterAmount.SendEnterAmountPayload
import javax.inject.Inject

class ChatsNavigator @Inject constructor(
    navigationHolder: NavigationHolder,
) : BaseNavigator(navigationHolder), ChatsRouter {
    override fun openChatFeed(payload: ChatFeedPayload) {
        performNavigation(
            actionId = R.id.action_global_to_chatFeedFragment,
            args = payload.toPayloadBundle()
        )
    }

    override fun openChatSearch() {
        performNavigation(R.id.action_global_to_chatSearchFragment)
    }

    override fun openAddContact() {
        performNavigation(R.id.action_global_to_addContactFragment)
    }

    override fun openScan() {
        if (isCurrentDestination(R.id.scanQrFragment)) return
        performNavigation(R.id.action_global_to_scan_graph)
    }

    override fun openEnterAmount(payload: SendEnterAmountPayload) {
        performNavigation(
            actionId = R.id.action_global_to_send_enter_amount_graph,
            args = payload.toPayloadBundle()
        )
    }

    override fun openMessageRequests() {
        performNavigation(R.id.action_global_to_chatRequestsListFragment)
    }
}
