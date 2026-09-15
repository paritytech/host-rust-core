package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.AsTuple
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchSignature
import io.paritytech.polkadotapp.feature_account_api.domain.model.PersonPublicKey
import kotlinx.serialization.Serializable

@Serializable
@AsTuple
class RegistrationOwnershipProof(
    val memberKey: PersonPublicKey,
    val proof: BandersnatchSignature
)
