package io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers

import androidx.lifecycle.SavedStateHandle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.loading.LoadingState
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.common.utils.withLoading
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor.ChatWithPlayersInteractor
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.GamePlayer
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers.models.ContactStatus
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers.models.GamePlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers.models.PlayerAction
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import javax.inject.Inject

@HiltViewModel
class ChatWithPlayersViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val interactor: ChatWithPlayersInteractor,
    private val router: VideoGameRouter
) : BaseViewModel() {
    private val payload = savedStateHandle.getPayload<ChatWithPlayersPayload>()
    private val gameIndex = GameIndex(payload.gameIndex)

    private val gamePlayers = interactor.subscribeGamePlayers(gameIndex)
        .shareInBackground()

    private val addingPlayerIds = MutableStateFlow<Set<AccountId>>(emptySet())

    val state = combine(gamePlayers, addingPlayerIds) { players, addingIds ->
        players.map { player -> player.toUi(isAdding = player.accountId in addingIds) }
    }
        .withLoading("ChatWithPlayersViewModel")
        .stateIn(this, SharingStarted.Eagerly, LoadingState.Loading)

    fun onPlayerAction(player: GamePlayerUiModel, action: PlayerAction) {
        when (action) {
            PlayerAction.ADD -> addContact(player)
            PlayerAction.MESSAGE -> messagePlayer(player)
        }
    }

    fun onBackClick() {
        router.back()
    }

    private fun addContact(player: GamePlayerUiModel) = launchUnit {
        addingPlayerIds.update { it + player.accountId }

        interactor.addGameContact(gameIndex, player.accountId)
            .onSuccess { openChatFeed(player.accountId) }
            .onFailure { showError(it) }

        addingPlayerIds.update { it - player.accountId }
    }

    private fun messagePlayer(player: GamePlayerUiModel) {
        openChatFeed(player.accountId)
    }

    private fun openChatFeed(contactAccountId: AccountId) {
        val payload = ChatFeedPayload.existingContactChat(contactAccountId)
        router.openChatFeed(payload)
    }

    private fun GamePlayer.toUi(isAdding: Boolean): GamePlayerUiModel {
        val contactStatus = when {
            isAdding -> ContactStatus.ADDING
            isAdded -> ContactStatus.ADDED
            else -> ContactStatus.NOT_ADDED
        }
        return GamePlayerUiModel(
            accountId = accountId,
            displayName = displayName,
            avatarUri = avatarUri,
            contactStatus = contactStatus
        )
    }
}
