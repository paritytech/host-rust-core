package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.datasource

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.api.queryNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_members_api.data.model.ringIndex
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.model.isAliasUpToDate
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.accountToAlias
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.people
import io.paritytech.polkadotapp.feature_people_impl.data.repository.getPeopleRingRoot
import io.paritytech.polkadotapp.feature_people_impl.data.repository.getPersonMember

abstract class StoragePeopleOriginsDataSource(
    private val membersRepository: MembersRepository,
) : PeopleOriginsDataSource {
    abstract suspend fun <R> query(chainId: ChainId, query: suspend StorageQueryContext.() -> R): R

    override suspend fun isAliasUpToDate(
        chainId: ChainId,
        aliasAccountId: AccountId,
        personId: PersonId,
    ): Boolean {
        val alias = query(chainId) {
            metadata.people.accountToAlias.query(aliasAccountId)
        } ?: return false

        val personRecord = query(chainId) {
            metadata.people.people.queryNonNull(personId)
        }

        val memberRecord = membersRepository.getPersonMember(
            chainId = chainId,
            key = personRecord.key,
            consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
        ).getOrThrow() ?: return false

        val ringRoot = membersRepository.getPeopleRingRoot(
            chainId = chainId,
            ringIndex = alias.ring,
            consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
        )
            .logFailure("Failed to get people ring root")
            .getOrNull()
            ?: return false

        val ringMatches = alias.ring == memberRecord.ringIndex
        val upToDateInRing = ringRoot.isAliasUpToDate(alias)

        return ringMatches && upToDateInRing
    }
}
