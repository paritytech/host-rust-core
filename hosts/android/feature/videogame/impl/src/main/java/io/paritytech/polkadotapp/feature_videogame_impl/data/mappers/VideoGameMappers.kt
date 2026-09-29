package io.paritytech.polkadotapp.feature_videogame_impl.data.mappers

import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import io.paritytech.polkadotapp.database.model.VideoGameVoteLocal
import io.paritytech.polkadotapp.database.model.VideoGameVoteLocal.VoteLocal
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameVote
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.Vote

fun VideoGameVoteLocal.toDomain() = VideoGameVote(
    accountId = accountId.intoAccountId(),
    roundIndex = roundIndex,
    playerIndex = playerIndex,
    vote = vote.toDomain(),
    gameIndex = GameIndex(gameIndex)
)

fun VideoGameVote.toLocal() = VideoGameVoteLocal(
    accountId = accountId.value,
    roundIndex = roundIndex,
    playerIndex = playerIndex,
    vote = vote.toLocal(),
    gameIndex = gameIndex.value
)

private fun VoteLocal.toDomain(): Vote = when (this) {
    VoteLocal.PERSON -> Vote.Person
    VoteLocal.NON_PERSON -> Vote.NonPerson
    VoteLocal.NOT_PARTICIPATED -> Vote.NotParticipated
}

private fun Vote.toLocal(): VoteLocal = when (this) {
    Vote.Person -> VoteLocal.PERSON
    Vote.NonPerson -> VoteLocal.NON_PERSON
    Vote.NotParticipated -> VoteLocal.NOT_PARTICIPATED
}
