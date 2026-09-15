package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.SerializedFallback
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.ByteArraySerializable
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

typealias MobRuleCaseId = BigIntegerSerializable

@Serializable
class MobRuleOpenCase(
    val details: OpenCaseDetails,
    val tally: VoteTally,
)

@Serializable
class MobRuleDoneCase(
    val verdict: MobRuleVote
)

@Serializable
class OpenCaseDetails(
    val statement: VoteCaseStatement
)

@Serializable
class VoteTally(
    val contempt: BigIntegerSerializable
)

@Serializable
@SerializedFallback("Unknown")
sealed class VoteCaseStatement {
    @Serializable
    class ProofOfInk(
        @SerialName("design")
        val tattooId: TattooId,
        val evidence: EvidenceHash,
        @SerialName("probable_acceptable")
        val probableAcceptable: Boolean,
    ) : VoteCaseStatement()

    @Serializable
    class IdentityCredential(
        val platform: IdentityPlatform,
        val evidence: String
    ) : VoteCaseStatement()

    @Serializable
    class UsernameValid(
        val username: String
    ) : VoteCaseStatement()

    data object Unknown : VoteCaseStatement()
}

@Serializable
sealed class IdentityPlatform {
    @Serializable
    class Twitter(override val username: String) : IdentityPlatform()

    @Serializable
    class Github(override val username: String) : IdentityPlatform()

    @Serializable
    class Discord(@SerialName("display_and_tag") override val username: String) : IdentityPlatform()

    abstract val username: String

    val platformName: String
        get() = when (this) {
            is Discord -> "Discord"
            is Github -> "Github"
            is Twitter -> "Twitter"
        }
}

typealias EvidenceHash = ByteArraySerializable
