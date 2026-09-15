package io.paritytech.polkadotapp.feature_chats_impl.domain.interactors

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_chats_api.domain.interactors.ChatFaqInteractor
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.MessageDeliveryDelay
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqQuestion
import io.paritytech.polkadotapp.feature_chats_impl.data.storage.AskedFaqQuestionsStorage
import io.paritytech.polkadotapp.feature_chats_impl.domain.ChatEngine
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class RealChatFaqInteractor @Inject constructor(
    private val storage: AskedFaqQuestionsStorage,
    private val chatEngine: ChatEngine,
    @ApplicationContext private val context: Context
) : ChatFaqInteractor {
    override fun observeClickedQuestions(botId: String): Flow<Set<Int>> {
        return storage.observeAskedQuestions(botId)
    }

    override suspend fun askQuestion(botId: String, question: FaqQuestion) {
        storage.markQuestionAsAsked(botId, question.resId)

        chatEngine.sendUserMessage(
            chatId = ChatId.fromChatBotId(botId),
            content = ChatMessage.Content.Text(context.getString(question.resId))
        )

        chatEngine.sendBotMessage(
            botId = botId,
            content = ChatMessage.Content.Text(context.getString(question.answerResId)),
            deliveryDelay = MessageDeliveryDelay.HUMAN_INTERACTION
        )
    }
}
