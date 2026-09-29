package io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked

import io.paritytech.polkadotapp.feature_transactions.api.data.tracked.ExtrinsicTag
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson

/**
 * Everything the repository needs to submit a vote/registration as a tracked extrinsic and record the override
 * target: the [tag] identifying the tracked tx, the [player] whose `VideoGame.Players` row it affects, and the
 * [gameIndex] used to synthesize that row when the chain has none yet.
 */
class VideoGameTrackedSubmission(
    val tag: ExtrinsicTag,
    val player: OnChainAccountOrPerson,
    val gameIndex: GameIndex,
)
