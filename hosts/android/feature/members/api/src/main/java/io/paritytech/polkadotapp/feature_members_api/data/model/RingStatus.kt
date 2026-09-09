package io.paritytech.polkadotapp.feature_members_api.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
class RingStatus(
    val total: Int,
    val included: Int,
    @SerialName("immutable_since")
    val immutableSince: Long? = null
)

fun RingStatus.includesKey(position: RingPosition): Boolean {
    val ringPosition = position.ringPosition ?: return false

    return included > ringPosition
}
