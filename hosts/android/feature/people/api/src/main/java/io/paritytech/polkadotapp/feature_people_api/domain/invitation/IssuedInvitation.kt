package io.paritytech.polkadotapp.feature_people_api.domain.invitation

import io.novasama.substrate_sdk_android.runtime.definitions.types.generics.MultiSignature
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.EncodedPublicKey
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount

data class IssuedInvitation(
    val invitee: MetaAccount,
    val inviter: AccountId,
    val ticket: EncodedPublicKey,
    val signature: MultiSignature,
    val dim: DimName,
)
