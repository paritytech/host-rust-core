package io.paritytech.polkadotapp.feature_videogame_impl.data.extension

import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.Struct
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.MultiSignature
import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.prepareForEncoding
import io.novasama.substrate_sdk_android.runtime.extrinsic.Nonce
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension
import io.paritytech.polkadotapp.chains.util.findNonceOrThrow
import io.paritytech.polkadotapp.common.domain.model.AccountId

class GameAsInvitedExtension(
    val inviter: AccountId,
    val ticket: AccountId,
    val signature: MultiSignature,
) : TransactionExtension {
    override val name: String = "GameAsInvited"

    override suspend fun implicit(): Any? {
        return null
    }

    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot
    ): Any? {
        val nonce = inheritedImplication.findNonceOrThrow()
        return GameAsInvitedData(
            nonce = nonce,
            inviter = inviter,
            ticket = ticket,
            signature = signature
        ).toEncodableInstance()
    }
}

class GameAsInvitedData(
    val nonce: Nonce,
    val inviter: AccountId,
    val ticket: AccountId,
    val signature: MultiSignature,
)

fun GameAsInvitedData.toEncodableInstance(): Any {
    return Struct.Instance(mapOf(
        "nonce" to nonce,
        "inviter" to inviter.value,
        "ticket" to ticket.value,
        "signature" to signature.prepareForEncoding()
    ))
}
