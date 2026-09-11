package io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked

import io.paritytech.polkadotapp.feature_transactions.api.data.tracked.ExtrinsicTag
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex

/**
 * Tags for the videogame's tracked extrinsics. The game-index suffix only disambiguates the per-game primary
 * key (so consecutive games don't collide); scoping to a specific player is done entirely via the tx
 * `additional` target, never by parsing the suffix back.
 */
object VideoGameExtrinsicTags {
    private const val NAMESPACE = "videogame"
    private const val VOTE = "vote"
    private const val REGISTER = "register"
    private const val CLAIM = "claim"

    val VOTE_PREFIX = ExtrinsicTag.fromParts(NAMESPACE, VOTE)
    val REGISTER_PREFIX = ExtrinsicTag.fromParts(NAMESPACE, REGISTER)

    fun vote(gameIndex: GameIndex): ExtrinsicTag = ExtrinsicTag.fromParts(NAMESPACE, VOTE, gameIndex.value)

    fun register(gameIndex: GameIndex): ExtrinsicTag = ExtrinsicTag.fromParts(NAMESPACE, REGISTER, gameIndex.value)

    fun claim(gameIndex: GameIndex): ExtrinsicTag = ExtrinsicTag.fromParts(NAMESPACE, CLAIM, gameIndex.value)
}
