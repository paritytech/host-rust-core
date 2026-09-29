package io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.serialization.Serializable

@Serializable
sealed class ProofOfInkCredibility {
    @Serializable
    @TransientStruct
    class Referred(val referrer: PersonId) : ProofOfInkCredibility()

    @Serializable
    @TransientStruct
    class Deposit(val deposit: Balance) : ProofOfInkCredibility()

    @Serializable
    @TransientStruct
    class Invited(val referrer: AccountId) : ProofOfInkCredibility()
}

fun ProofOfInkCredibility.isReferred(): Boolean {
    return this is ProofOfInkCredibility.Referred
}

fun ProofOfInkCredibility.isInvited(): Boolean {
    return this is ProofOfInkCredibility.Invited
}
