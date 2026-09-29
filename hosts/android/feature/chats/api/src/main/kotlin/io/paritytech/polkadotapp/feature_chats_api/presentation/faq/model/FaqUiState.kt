package io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model

import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

data class FaqUiState(
    val questions: ImmutableList<FaqQuestion> = persistentListOf()
)

interface FaqQuestion {
    val resId: Int
    val answerResId: Int
}
