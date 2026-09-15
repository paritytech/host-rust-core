package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlin.time.Duration

data class HistoricalGameInfo(
    val gameIndex: GameIndex,
    val gameTimestamp: Duration,
)

class GamesHistory(
    gamesHistory: List<HistoricalGameInfo>,
    val activeGamePresent: Boolean
) {
    private val gamesHistory = gamesHistory.sortedBy { it.gameIndex }

    fun currentGameIndex(): GameIndex {
        return lastHistoryItemIndex() ?: GameIndex.zero()
    }

    fun activeGame(): HistoricalGameInfo? {
        return gamesHistory.lastOrNull()?.takeIf { activeGamePresent }
    }

    private fun lastHistoryItemIndex(): GameIndex? {
        return gamesHistory.lastOrNull()?.gameIndex
    }

    fun pastGamesAfterInclusive(gameIndex: GameIndex): List<HistoricalGameInfo> {
        val gamesAfterGiven = gamesHistory.filter { it.gameIndex >= gameIndex }

        return if (activeGamePresent) {
            // Active game is present in game history as well, so we drop it
            gamesAfterGiven.dropLast(1)
        } else {
            gamesAfterGiven
        }
    }
}
