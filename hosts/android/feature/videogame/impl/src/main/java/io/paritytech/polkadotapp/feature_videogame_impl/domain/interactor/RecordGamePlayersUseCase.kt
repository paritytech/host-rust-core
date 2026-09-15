package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.GamePlayersRepository
import timber.log.Timber
import javax.inject.Inject

class RecordGamePlayersUseCase @Inject constructor(
    private val gamePlayersRepository: GamePlayersRepository
) {
    suspend operator fun invoke(gameInfo: VideoGameInfo) {
        val state = gameInfo.state
        if (state !is VideoGameState.InProgress) {
            Timber.d("Game state is not InProgress, skipping players recording")
            return
        }

        val allPlayers = state.rounds
            .flatMap { it.players }
            .distinct()

        if (allPlayers.isEmpty()) {
            Timber.d("No players to record for game ${gameInfo.index}")
            return
        }

        gamePlayersRepository.saveGamePlayers(gameInfo.index, allPlayers, gameInfo.gameStartMillis)
        Timber.d("Recorded ${allPlayers.size} players for game ${gameInfo.index}")
    }
}
