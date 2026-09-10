package io.paritytech.polkadotapp.feature_identity_api.domain.models

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.AsTuple
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import io.paritytech.polkadotapp.common.domain.model.AccountId
import kotlinx.serialization.Serializable

@Serializable
class PersonalIdentity(
    val account: AccountId,
    val banned: Boolean,
    val pendingJudgements: List<PendingJudgementTuple>,
    val usernameLastReportedAt: BigIntegerSerializable? = null,
)

@Serializable
@AsTuple
data class PendingJudgementTuple(
    val judgement: IdentityCredentialPlatform,
    val index: BigIntegerSerializable
)
