package io.paritytech.polkadotapp.feature_become_citizen_impl.data.signer.referral

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import io.novasama.substrate_sdk_android.runtime.extrinsic.Nonce
import kotlinx.serialization.Contextual
import kotlinx.serialization.Serializable

@Serializable
sealed class AsProofOfInkParticipantInfo {
    @Serializable
    @TransientStruct
    class AsApplyWithSig(val nonce: @Contextual Nonce) : AsProofOfInkParticipantInfo()

    @Serializable
    @TransientStruct
    class AsReferred(val nonce: @Contextual Nonce) : AsProofOfInkParticipantInfo()

    @Serializable
    @TransientStruct
    class AsInvited(val nonce: @Contextual Nonce) : AsProofOfInkParticipantInfo()
}
