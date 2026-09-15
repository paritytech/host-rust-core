package io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain.models

import io.paritytech.polkadotapp.chains.network.binding.bindAccountId
import io.paritytech.polkadotapp.common.data.substrate.castToStruct
import io.paritytech.polkadotapp.common.domain.model.AccountId

class UsernameInformation(
    val owner: AccountId
)

fun bindUsernameInformation(decoded: Any?): UsernameInformation {
    val struct = decoded.castToStruct()

    return UsernameInformation(
        owner = bindAccountId(struct["owner"])
    )
}
