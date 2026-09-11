package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePlayerRoundKey
import kotlin.math.ceil

/**
 * Mirrors the chain's matchmaking group assignment: player `i` belongs to group
 * `i % numberOfGroups` each round; a group holds every index
 * `groupIndex + slot * numberOfGroups` below `playerCount`.
 */
object VideoGameGroupAssignment {
    fun roundKeys(
        playerCount: Int,
        groupSize: Int,
        playerIndexes: List<Int>,
        includeSelf: Boolean,
    ): List<OnChainVideoGamePlayerRoundKey> {
        val numberOfGroups = ceil(playerCount / groupSize.toDouble()).toInt()

        return buildList {
            playerIndexes.forEachIndexed { round, myIndex ->
                val groupIndex = myIndex % numberOfGroups
                for (slot in 0 until groupSize) {
                    val memberIndex = groupIndex + slot * numberOfGroups
                    if (memberIndex >= playerCount) continue
                    if (!includeSelf && memberIndex == myIndex) continue
                    add(OnChainVideoGamePlayerRoundKey(round, memberIndex))
                }
            }
        }
    }
}
