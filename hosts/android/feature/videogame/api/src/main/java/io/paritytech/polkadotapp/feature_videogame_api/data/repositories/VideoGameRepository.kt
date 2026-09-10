package io.paritytech.polkadotapp.feature_videogame_api.data.repositories

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.EncodedPublicKey
import kotlinx.coroutines.flow.Flow

interface VideoGameRepository {
    fun subscribePendingInvites(chainId: ChainId, inviter: AccountId, ticket: EncodedPublicKey): Flow<Boolean>
}
