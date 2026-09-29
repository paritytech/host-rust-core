package io.paritytech.polkadotapp.feature_videogame_impl.data.extension

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension
import io.paritytech.polkadotapp.chains.util.findNonceOrThrow
import io.paritytech.polkadotapp.chains.util.scaleEncodeSerializable
import kotlinx.serialization.Serializable

class ScoreAsParticipantExtension() : TransactionExtension {
    override val name: String = "ScoreAsParticipant"

    override suspend fun implicit(): Any? {
        return null
    }

    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot
    ): Any? {
        val nonce = inheritedImplication.findNonceOrThrow()
        return ScoreAsParticipantData(nonce).scaleEncodeSerializable()
    }

    @Serializable
    private class ScoreAsParticipantData(
        val nonce: BigIntegerSerializable
    )
}
