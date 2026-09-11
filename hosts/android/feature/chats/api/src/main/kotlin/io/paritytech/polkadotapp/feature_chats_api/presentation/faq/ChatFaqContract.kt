package io.paritytech.polkadotapp.feature_chats_api.presentation.faq

import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqQuestion
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqUiState
import kotlinx.coroutines.flow.StateFlow

interface ChatFaqContract {
    val state: StateFlow<FaqUiState>

    fun askQuestion(question: FaqQuestion)
}
