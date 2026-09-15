package io.paritytech.polkadotapp.app.root.navigation.mobrules

import io.paritytech.polkadotapp.app.R
import io.paritytech.polkadotapp.app.root.navigation.BaseNavigator
import io.paritytech.polkadotapp.app.root.navigation.NavigationHolder
import io.paritytech.polkadotapp.common.utils.toPayloadBundle
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.MobRulesRouter
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.MediaEvidenceDetailPayload
import jakarta.inject.Inject

class MobRulesNavigator @Inject constructor(
    navigationHolder: NavigationHolder,
) : BaseNavigator(navigationHolder), MobRulesRouter {
    override fun openEvidenceDetail(payload: MediaEvidenceDetailPayload) {
        performNavigation(
            actionId = R.id.action_global_to_evidenceDetailFragment,
            args = payload.toPayloadBundle()
        )
    }

    override fun openChatFeed(payload: ChatFeedPayload) {
        performNavigation(
            actionId = R.id.action_global_to_chatFeedFragment,
            args = payload.toPayloadBundle()
        )
    }
}
