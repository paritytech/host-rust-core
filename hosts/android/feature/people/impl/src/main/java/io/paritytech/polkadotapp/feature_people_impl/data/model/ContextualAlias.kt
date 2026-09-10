package io.paritytech.polkadotapp.feature_people_impl.data.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.ByteArraySerializable
import io.paritytech.polkadotapp.feature_members_api.data.model.RingIndex
import io.paritytech.polkadotapp.feature_members_api.data.model.RingRevision
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
class RevisedContextualAlias(
    @SerialName("ca")
    val contextualAlias: ContextualAlias,
    val ring: RingIndex,
    val revision: RingRevision
)

@Serializable
class ContextualAlias(
    val alias: PersonalAlias,
    val context: ByteArraySerializable
)
