package io.paritytech.polkadotapp.feature_videogame_impl.data.storages

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

private const val LAST_GAME_DISMISSED_INDEX = "LastGameDismissedIndex.Key"

interface VideoGameHistoryRestoringStorage {
    fun subscribeLastDismissedIndex(): Flow<GameIndex>

    suspend fun saveLastDismissedIndex(gameIndex: GameIndex)
}

class RealVideoGameHistoryRestoringStorage @Inject constructor(
    private val preferences: Preferences
) : VideoGameHistoryRestoringStorage {
    override fun subscribeLastDismissedIndex(): Flow<GameIndex> = preferences
        .intFlow(LAST_GAME_DISMISSED_INDEX, 0)
        .map { GameIndex(it) }

    override suspend fun saveLastDismissedIndex(gameIndex: GameIndex) {
        preferences.putInt(LAST_GAME_DISMISSED_INDEX, gameIndex.value)
    }
}
