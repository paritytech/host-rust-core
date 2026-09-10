package io.paritytech.polkadotapp.feature_mobrules_api.domain.model

import java.math.BigInteger

@JvmInline
value class VotingPoints(val value: BigInteger) : Comparable<VotingPoints> {
    // For extensions
    companion object;

    operator fun div(votingPoints: VotingPoints): BigInteger {
        return value.div(votingPoints.value)
    }

    operator fun rem(votingPoints: VotingPoints): VotingPoints {
        return value.rem(votingPoints.value).intoVotingPoints()
    }

    override fun compareTo(other: VotingPoints): Int {
        return value.compareTo(other.value)
    }
}

fun BigInteger.intoVotingPoints() = VotingPoints(this)
