package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.common.domain.model.AccountId
import kotlinx.serialization.Serializable

@Serializable
sealed class OnChainAccountOrPerson {
    @Serializable
    @TransientStruct
    data class Account(val accountId: AccountId) : OnChainAccountOrPerson()

    @Serializable
    @TransientStruct
    data class Person(val alias: BandersnatchAlias) : OnChainAccountOrPerson()
}
