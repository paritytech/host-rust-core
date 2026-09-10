package io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models

import androidx.annotation.Keep
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.SerializedFallback
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
@SerializedFallback("Unknown")
sealed class ProofOfInkCandidate {
    @Serializable
    class Applied(
        val entropy: ProofOfInkEntropy,
        @SerialName("cred")
        val credibility: ProofOfInkCredibility,
    ) : ProofOfInkCandidate()

    @Serializable
    class Selected(
        val since: BlockNumber,
        val judging: BigIntegerSerializable?,
        @SerialName("design")
        val tattooId: TattooId,
        val allocation: ProofOfInkAllocation,
        @SerialName("cred")
        val credibility: ProofOfInkCredibility,
    ) : ProofOfInkCandidate()

    @Serializable
    data class Proven(val wasReferred: Boolean, val wasInvited: Boolean) : ProofOfInkCandidate()

    @Serializable
    @Keep
    data object Unknown : ProofOfInkCandidate()
}
