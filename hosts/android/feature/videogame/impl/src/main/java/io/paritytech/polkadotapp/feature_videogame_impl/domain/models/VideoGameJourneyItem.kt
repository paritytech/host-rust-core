package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlin.time.Duration

data class VideoGameJourneyItem(
    val gameIndex: GameIndex,
    val status: Status,
    val timestamp: Duration?
) {
    enum class Status {
        PENDING, SUCCESSFUL, FAILED, FUTURE
    }
}

fun List<VideoGameJourneyItem>.lastNonFutureGame(): VideoGameJourneyItem? {
    return lastOrNull { it.status != VideoGameJourneyItem.Status.FUTURE }
}

fun List<VideoGameJourneyItem>.findByGameIndex(gameIndex: GameIndex): VideoGameJourneyItem? {
    return find { it.gameIndex == gameIndex }
}
