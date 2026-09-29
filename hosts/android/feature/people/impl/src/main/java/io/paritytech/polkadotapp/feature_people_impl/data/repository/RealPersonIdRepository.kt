package io.paritytech.polkadotapp.feature_people_impl.data.repository

import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.queryNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.feature_people_api.data.repository.PersonIdRepository
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.nextPersonId
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.people
import io.paritytech.polkadotapp.feature_people_impl.data.storage.PersonIdStorage
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class RealPersonIdRepository @Inject constructor(
    private val personIdStorage: PersonIdStorage,
    @RemoteSourceQualifier private val remoteStorageDataSource: StorageDataSource
) : PersonIdRepository {
    override fun personIdFlow(): Flow<PersonId?> {
        return personIdStorage.subscribePersonId()
    }

    override suspend fun getPersonId(): PersonId? {
        return personIdStorage.getPersonId()
    }

    override suspend fun getNextAvailablePersonId(chainId: ChainId): Result<PersonId> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.people.nextPersonId.queryNonNull()
        }
    }
}
