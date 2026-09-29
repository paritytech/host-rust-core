package io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.referral

import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.Nonce
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.TransactionExtension
import io.novasama.substrate_sdk_android.runtime.metadata.TransactionExtensionId
import io.paritytech.polkadotapp.chains.util.findNonceOrThrow
import io.paritytech.polkadotapp.chains.util.scaleEncodeSerializable

class AsProofOfInkParticipant(val variant: Variant) : TransactionExtension {
    enum class Variant {
        AS_APPLY_WITH_SIG, AS_REFERRED, AS_INVITED
    }

    override val name: TransactionExtensionId = "AsProofOfInkParticipant"

    override suspend fun explicit(inheritedImplication: InheritedImplication, runtimeSnapshot: RuntimeSnapshot): Any? {
        val nonce = inheritedImplication.findNonceOrThrow()
        return createParticipantInfo(nonce, variant).scaleEncodeSerializable()
    }

    override suspend fun implicit(): Any? {
        return null
    }

    private fun createParticipantInfo(nonce: Nonce, variant: Variant): AsProofOfInkParticipantInfo {
        return when (variant) {
            Variant.AS_APPLY_WITH_SIG -> AsProofOfInkParticipantInfo.AsApplyWithSig(nonce)
            Variant.AS_REFERRED -> AsProofOfInkParticipantInfo.AsReferred(nonce)
            Variant.AS_INVITED -> AsProofOfInkParticipantInfo.AsInvited(nonce)
        }
    }
}
