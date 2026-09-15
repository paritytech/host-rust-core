package io.paritytech.polkadotapp.feature_mobrules_impl.presentation

import io.paritytech.polkadotapp.common.presentation.navigation.ReturnableRouter
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.MediaEvidenceDetailPayload

interface MobRulesRouter : ReturnableRouter {
    fun openEvidenceDetail(payload: MediaEvidenceDetailPayload)

    fun openChatFeed(payload: ChatFeedPayload)
}
