package io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.BinaryScale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.annotations.EnumIndex
import io.paritytech.polkadotapp.common.domain.model.AccountId
import kotlinx.serialization.Serializable

@Serializable
sealed interface GestureAcceptanceMessage {
    val roundIndex: Int
    val acceptorAccountId: AccountId

    @Serializable
    @EnumIndex(0)
    class Accept(
        override val roundIndex: Int,
        override val acceptorAccountId: AccountId
    ) : GestureAcceptanceMessage

    @Serializable
    @EnumIndex(1)
    class Unaccept(
        override val roundIndex: Int,
        override val acceptorAccountId: AccountId
    ) : GestureAcceptanceMessage

    companion object {
        fun encode(message: GestureAcceptanceMessage): ByteArray {
            return BinaryScale.encodeToByteArray(serializer(), message)
        }

        fun decode(data: ByteArray): GestureAcceptanceMessage {
            return BinaryScale.decodeFromByteArray(serializer(), data)
        }
    }
}
