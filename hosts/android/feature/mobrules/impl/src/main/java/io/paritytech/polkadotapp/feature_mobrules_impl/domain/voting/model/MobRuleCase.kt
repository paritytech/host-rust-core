package io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import java.math.BigInteger

class MobRuleCase(
    val id: BigInteger,
    val isSensitive: Boolean,
    val statement: MobRuleCaseStatement,
)

sealed interface MobRuleCaseStatement {
    sealed interface ProofOfInk : MobRuleCaseStatement {
        val tattooId: TattooId
        val tattooFamilyId: ByteArray

        val evidenceHash: ByteArray

        class Video(
            override val tattooId: TattooId,
            override val tattooFamilyId: ByteArray,
            override val evidenceHash: ByteArray
        ) : ProofOfInk

        class Photo(
            override val tattooId: TattooId,
            override val tattooFamilyId: ByteArray,
            override val evidenceHash: ByteArray
        ) : ProofOfInk
    }

    class IdentityCredential(
        val platform: IdentityCredentialPlatform,
        val userPlatformTag: String,
        val evidence: String
    ) : MobRuleCaseStatement

    class UsernameValid(
        val username: String
    ) : MobRuleCaseStatement
}
