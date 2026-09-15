package io.paritytech.polkadotapp.feature_chats_api.presentation.faq

import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.feature_chats_api.domain.interactors.ChatFaqInteractor
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatExtensionId
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqQuestion
import io.paritytech.polkadotapp.feature_chats_api.presentation.faq.model.FaqUiState
import kotlinx.collections.immutable.toPersistentList
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

@HiltViewModel(assistedFactory = ChatFaqViewModel.Factory::class)
class ChatFaqViewModel @AssistedInject constructor(
    @Assisted private val botId: ChatExtensionId,
    @Assisted private val allQuestions: List<FaqQuestion>,
    private val interactor: ChatFaqInteractor
) : BaseViewModel(), ChatFaqContract {
    @AssistedFactory
    interface Factory {
        fun create(botId: ChatExtensionId, allQuestions: List<FaqQuestion>): ChatFaqViewModel
    }

    override val state = interactor.observeClickedQuestions(botId)
        .map { clickedQuestions ->
            val visibleQuestions = allQuestions.filterNot { question ->
                clickedQuestions.contains(question.resId)
            }
            FaqUiState(questions = visibleQuestions.toPersistentList())
        }
        .stateIn(this, SharingStarted.Eagerly, FaqUiState())

    override fun askQuestion(question: FaqQuestion) = launchUnit {
        interactor.askQuestion(botId, question)
    }
}
