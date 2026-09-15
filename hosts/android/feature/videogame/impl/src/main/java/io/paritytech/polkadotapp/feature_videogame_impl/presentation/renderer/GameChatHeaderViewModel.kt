package io.paritytech.polkadotapp.feature_videogame_impl.presentation.renderer

import androidx.compose.runtime.Immutable
import androidx.lifecycle.SavedStateHandle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.design.components.avatar.AvatarUiModel
import io.paritytech.polkadotapp.design.configs.colors.AvatarColorScheme
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ContactAvatar
import io.paritytech.polkadotapp.feature_chats_api.domain.model.computeChatId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.contactOrNull
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.toOpenChatRequest
import io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor.GameChatHeaderInteractor
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

@HiltViewModel
class GameChatHeaderViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val gameChatHeaderInteractor: GameChatHeaderInteractor
) : BaseViewModel() {
    private val payload: ChatFeedPayload = savedStateHandle.getPayload()
    private val chatId = payload.toOpenChatRequest().computeChatId()
    private val contactAccountId = chatId.contactOrNull()?.contactAccountId

    val state: StateFlow<GameChatHeaderState> = flowOf {
        val accountId = contactAccountId ?: return@flowOf GameChatHeaderState()
        val headerData = gameChatHeaderInteractor.getGameChatHeaderData(accountId)
            ?: return@flowOf GameChatHeaderState()
        GameChatHeaderState(
            username = headerData.username,
            avatarModel = headerData.avatar.toUi(),
            gameTimestamp = headerData.gameTimestamp
        )
    }.stateInBackground(initialValue = GameChatHeaderState())
}

private fun ContactAvatar.toUi(): AvatarUiModel = when (this) {
    is ContactAvatar.Account -> AvatarUiModel.Name(name, AvatarColorScheme.from(themeSeed))
    is ContactAvatar.Url -> AvatarUiModel.Image(url)
}

@Immutable
data class GameChatHeaderState(
    val username: String? = null,
    val avatarModel: AvatarUiModel? = null,
    val gameTimestamp: Timestamp? = null
)
