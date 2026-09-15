package io.paritytech.polkadotapp.feature_people_api.domain.models

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import kotlinx.serialization.Serializable
import java.math.BigInteger

@JvmInline
@Serializable
value class PersonId private constructor(val id: BigIntegerSerializable) {
    companion object {
        fun BigInteger.intoPersonId(): PersonId {
            return PersonId(this)
        }
    }
}
