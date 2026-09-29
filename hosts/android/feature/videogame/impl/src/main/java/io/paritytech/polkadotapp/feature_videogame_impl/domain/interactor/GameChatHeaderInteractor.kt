package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.feature_chats_api.domain.ContactDisplayProvider
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ContactAvatar
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.GamePlayersRepository
import javax.inject.Inject

class GameChatHeaderInteractor @Inject constructor(
    private val contactDisplayProvider: ContactDisplayProvider,
    private val gamePlayersRepository: GamePlayersRepository
) {
    suspend fun getGameChatHeaderData(contactAccountId: AccountId): GameChatHeaderData? {
        val contactDisplay = contactDisplayProvider.getContactDisplay(contactAccountId) ?: return null
        val gameTimestamp = gamePlayersRepository.getLatestGameTimestampForPlayer(contactAccountId)
        return GameChatHeaderData(
            username = contactDisplay.username,
            avatar = contactDisplay.avatar,
            gameTimestamp = gameTimestamp
        )
    }
}

data class GameChatHeaderData(
    val username: String,
    val avatar: ContactAvatar,
    val gameTimestamp: Timestamp?
)
