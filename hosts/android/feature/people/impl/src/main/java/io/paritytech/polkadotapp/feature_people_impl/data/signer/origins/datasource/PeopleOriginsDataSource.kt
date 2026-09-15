package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.datasource

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService

interface PeopleOriginsDataSource {
    val extrinsicService: ExtrinsicService

    suspend fun isAliasUpToDate(chainId: ChainId, aliasAccountId: AccountId, personId: PersonId): Boolean

    suspend fun currentBlockNumber(chainId: ChainId): BlockNumber
}
