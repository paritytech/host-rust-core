package io.paritytech.polkadotapp.feature_people_api.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import kotlinx.coroutines.flow.Flow

interface PersonIdRepository {
    fun personIdFlow(): Flow<PersonId?>

    suspend fun getPersonId(): PersonId?

    suspend fun getNextAvailablePersonId(chainId: ChainId): Result<PersonId>
}

suspend fun PersonIdRepository.getPersonIdOrThrow(): PersonId {
    return requireNotNull(getPersonId())
}
