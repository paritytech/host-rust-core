package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.RelativeMultiLocation
import kotlinx.serialization.Serializable

@Serializable
class OnChainActiveEvent(
    val id: DataByteArray,
    val info: OnChainAirdropEventInfo,
    val status: OnChainAirdropStatus,
)

@Serializable
class OnChainAirdropEventInfo(
    val prize: OnChainAirdropPrize,
    val registrationStarts: Long,
    val drawTime: Long,
    val endTime: Long,
)

@Serializable
class OnChainAirdropPrize(
    // The runtime identifies the prize asset by an XCM Location, not a scalar id; the Asset Hub
    // asset index lives in its GeneralIndex junction (see RelativeMultiLocation.firstGeneralIndex).
    val assetId: RelativeMultiLocation,
    val assetAmount: BigIntegerSerializable,
    val maxWinners: Int,
    val winnerCap: Int,
)

@Serializable
sealed class OnChainAirdropStatus {
    @Serializable
    object Scheduled : OnChainAirdropStatus()

    @Serializable
    class Registering(val totalParticipants: Int) : OnChainAirdropStatus()

    @Serializable
    class DrawWinners(
        val totalParticipants: Int,
        val effectiveWinners: Int,
        val winnersAdded: Int,
        val fromWinnerKey: DataByteArray,
    ) : OnChainAirdropStatus()

    @Serializable
    class Claiming(
        val totalParticipants: Int,
        val effectiveWinners: Int,
        val claimed: Int,
    ) : OnChainAirdropStatus()

    @Serializable
    class ClearingRegistrations(
        val totalParticipants: Int,
        val effectiveWinners: Int,
        val claimed: Int,
        val cleanedRegistrations: Int,
    ) : OnChainAirdropStatus()

    @Serializable
    class ClearingWinners(
        val totalParticipants: Int,
        val effectiveWinners: Int,
        val claimed: Int,
        val cleanedWinners: Int,
    ) : OnChainAirdropStatus()

    @Serializable
    class Finalizing(
        val effectiveWinners: Int,
        val claimed: Int,
    ) : OnChainAirdropStatus()
}

val OnChainAirdropStatus.totalParticipants: Int?
    get() = when (this) {
        is OnChainAirdropStatus.Registering -> totalParticipants
        is OnChainAirdropStatus.DrawWinners -> totalParticipants
        is OnChainAirdropStatus.Claiming -> totalParticipants
        is OnChainAirdropStatus.ClearingRegistrations -> totalParticipants
        is OnChainAirdropStatus.ClearingWinners -> totalParticipants
        is OnChainAirdropStatus.Scheduled,
        is OnChainAirdropStatus.Finalizing -> null
    }
