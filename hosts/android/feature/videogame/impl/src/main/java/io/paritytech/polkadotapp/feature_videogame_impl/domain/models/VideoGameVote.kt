package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex

class VideoGameVote(
    val accountId: AccountId,
    val roundIndex: Int,
    val playerIndex: Int,
    val vote: Vote,
    val gameIndex: GameIndex
)

sealed interface Vote {
    object Person : Vote
    object NonPerson : Vote
    object NotParticipated : Vote
}
