package io.paritytech.polkadotapp.feature_chats_impl.presentation.polkadotpeerbot.models

import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqQuestion

enum class PolkadotChatPeerBotQuestion(override val resId: Int, override val answerResId: Int) : FaqQuestion {
    WHO_IS_POLKADOT_PEER(R.string.chat_peer_faq_who_is_polkadot_peer, R.string.chat_peer_faq_who_is_polkadot_peer_answer),
    WHY_BECOME_A_PEER(R.string.chat_peer_faq_why_become_a_peer, R.string.chat_peer_faq_why_become_a_peer_answer),
    I_HAVE_OTHER_QUESTIONS(R.string.chat_peer_faq_i_have_other_questions, R.string.chat_peer_faq_i_have_other_questions_answer)
}
