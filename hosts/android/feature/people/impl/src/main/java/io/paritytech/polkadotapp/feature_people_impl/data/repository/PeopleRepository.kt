package io.paritytech.polkadotapp.feature_people_impl.data.repository

import io.paritytech.polkadotapp.chains.di.LocalSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.queryNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_people_api.data.model.PersonRecord
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.model.RevisedContextualAlias
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.accountToAlias
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.people
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

interface PeopleRepository {
    fun subscribePerson(chainId: ChainId, personId: PersonId): Flow<PersonRecord?>

    fun subscribeRegisteredAlias(chainId: ChainId, aliasAccountId: AccountId): Flow<RevisedContextualAlias?>

    suspend fun person(chainId: ChainId, personId: PersonId): PersonRecord
}

class RealPeopleRepository @Inject constructor(
    @LocalSourceQualifier private val localStorageSource: StorageDataSource,
) : PeopleRepository {
    override fun subscribePerson(
        chainId: ChainId,
        personId: PersonId
    ): Flow<PersonRecord?> {
        return localStorageSource.subscribe(chainId) {
            metadata.people.people.observe(personId)
        }
    }

    override fun subscribeRegisteredAlias(
        chainId: ChainId,
        aliasAccountId: AccountId
    ): Flow<RevisedContextualAlias?> = localStorageSource.subscribe(chainId) {
        metadata.people.accountToAlias.observe(aliasAccountId)
    }

    override suspend fun person(chainId: ChainId, personId: PersonId): PersonRecord {
        return localStorageSource.query(chainId) {
            metadata.people.people.queryNonNull(personId)
        }
    }
}
