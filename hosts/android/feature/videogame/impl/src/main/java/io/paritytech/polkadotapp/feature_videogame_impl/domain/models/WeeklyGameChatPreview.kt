package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.common.domain.model.Timestamp

sealed interface WeeklyGameChatPreview {
    data class NewGameAnnounced(val timestamp: Timestamp) : WeeklyGameChatPreview

    data class Registered(val timestamp: Timestamp) : WeeklyGameChatPreview

    data object GameStarting : WeeklyGameChatPreview

    data object GamePending : WeeklyGameChatPreview

    data class GameSuccessful(val gamesLeft: Int) : WeeklyGameChatPreview

    data object PeerReached : WeeklyGameChatPreview

    data class GameFailed(val gamesLeft: Int) : WeeklyGameChatPreview
}
