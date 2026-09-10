package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import kotlinx.serialization.Serializable

@Serializable
sealed class OnChainAirdropRegistrationEntry {
    @Serializable
    class Alias(val participantOrigin: DataByteArray) : OnChainAirdropRegistrationEntry()

    @Serializable
    class Account(val accountId: DataByteArray) : OnChainAirdropRegistrationEntry()
}
