package io.paritytech.polkadotapp.feature_chats_api.domain.interactors

import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqQuestion
import kotlinx.coroutines.flow.Flow

interface ChatFaqInteractor {
    fun observeClickedQuestions(botId: String): Flow<Set<Int>>
    suspend fun askQuestion(botId: String, question: FaqQuestion)
}
