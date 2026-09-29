package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlinx.serialization.Serializable
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

// Positional SCALE mirror of pallet-game `Player`: field order and integer widths
// (Byte=u8, Short=u16, Int=u32, Long=u64) must match the Rust struct exactly.
@Serializable
data class OnChainVideoGamePlayerInfo(
    val firstGame: GameIndex,
    val registered: Boolean,
    val sentReport: Boolean,
    val earlyAttendanceEnactment: OnChainEarlyAttendanceEnactment?,
    val yesPerson: Byte,
    val noNotPerson: Byte,
    val expectedMaxVoteWeight: Short,
    val voteWeight: Byte,
    val credibility: OnChainGamePlayerCredibility
)

@Serializable
class OnChainEarlyAttendanceEnactment(
    val attendance: Boolean,
    val disposition: OnChainPlayerDisposition
)

// Variant names must match the runtime enum — decoded by name.
@Serializable
sealed class OnChainPlayerDisposition {
    @Serializable
    object Keep : OnChainPlayerDisposition()

    @Serializable
    object ArchiveKickable : OnChainPlayerDisposition()

    @Serializable
    object ArchiveUnkickable : OnChainPlayerDisposition()
}

@Serializable
sealed class OnChainGamePlayerCredibility {
    @Serializable
    object Invited : OnChainGamePlayerCredibility()

    @Serializable
    object Recognized : OnChainGamePlayerCredibility()

    @Serializable
    object Deposit : OnChainGamePlayerCredibility()
}

fun OnChainGamePlayerCredibility.isDeposit(): Boolean {
    return this is OnChainGamePlayerCredibility.Deposit
}

@OptIn(ExperimentalContracts::class)
fun OnChainVideoGamePlayerInfo?.isRegistered(): Boolean {
    contract {
        returns(true) implies (this@isRegistered != null)
    }

    return this?.registered == true
}

@OptIn(ExperimentalContracts::class)
fun OnChainVideoGamePlayerInfo?.canRegisterWithoutProvingCredibility(): Boolean {
    contract {
        returns(true) implies (this@canRegisterWithoutProvingCredibility != null)
    }

    return this != null
}
