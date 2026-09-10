package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.model

import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqQuestion

enum class TattooBotQuestion(override val resId: Int, override val answerResId: Int) : FaqQuestion {
    CAN_I_ALTER_LOCATION(R.string.chat_faq_proof_of_ink_question_alter_location, R.string.chat_faq_proof_of_ink_question_alter_location),
    HOW_SHOULD_I_FILM_THE_EVIDENCE(R.string.chat_faq_proof_of_ink_question_film_evidence, R.string.chat_faq_proof_of_ink_question_film_evidence),
    WHAT_HAPPENS_AFTER_SUBMISSION(R.string.chat_faq_proof_of_ink_question_after_submission, R.string.chat_faq_proof_of_ink_question_after_submission),
}
