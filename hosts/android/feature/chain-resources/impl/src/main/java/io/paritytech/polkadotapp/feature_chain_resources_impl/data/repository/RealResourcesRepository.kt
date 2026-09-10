package io.paritytech.polkadotapp.feature_chain_resources_impl.data.repository

import io.paritytech.polkadotapp.chains.di.LocalSourceQualifier
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.queryNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.mapNotNull
import io.paritytech.polkadotapp.common.utils.scale.toDomain
import io.paritytech.polkadotapp.feature_chain_resources_api.data.api.consumers
import io.paritytech.polkadotapp.feature_chain_resources_api.data.api.reservationDuration
import io.paritytech.polkadotapp.feature_chain_resources_api.data.api.resources
import io.paritytech.polkadotapp.feature_chain_resources_api.data.api.usernameOwnerOf
import io.paritytech.polkadotapp.feature_chain_resources_api.data.api.usernameReservationQueue
import io.paritytech.polkadotapp.feature_chain_resources_api.data.model.OnChainConsumerInfo
import io.paritytech.polkadotapp.feature_chain_resources_api.data.model.OnChainReservationQueueEntry
import io.paritytech.polkadotapp.feature_chain_resources_api.data.repository.ResourcesRepository
import io.paritytech.polkadotapp.feature_chain_resources_api.domain.model.ConsumerInfo
import io.paritytech.polkadotapp.feature_chain_resources_api.domain.model.UsernameReservation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

class RealResourcesRepository @Inject constructor(
    @RemoteSourceQualifier private val remoteStorageSource: StorageDataSource,
    @LocalSourceQualifier private val localStorageSource: StorageDataSource,
) : ResourcesRepository {
    override suspend fun consumerInfo(
        chainId: ChainId,
        accountId: AccountId,
    ): Result<ConsumerInfo?> {
        return remoteStorageSource.queryCatching(chainId) {
            val onChainInfo = metadata.resources.consumers.query(accountId)
            onChainInfo?.toDomain(accountId)
        }
    }

    override suspend fun consumerInfoLocal(
        chainId: ChainId,
        accountId: AccountId,
    ): Result<ConsumerInfo?> {
        return localStorageSource.queryCatching(chainId) {
            val onChainInfo = metadata.resources.consumers.query(accountId)
            onChainInfo?.toDomain(accountId)
        }
    }

    override fun consumerInfoFlow(chainId: ChainId, accountId: AccountId) =
        remoteStorageSource.consumerInfoLocalFlow(chainId, accountId)

    override fun consumerInfoLocalFlow(chainId: ChainId, accountId: AccountId) =
        localStorageSource.consumerInfoLocalFlow(chainId, accountId)

    private fun StorageDataSource.consumerInfoLocalFlow(
        chainId: ChainId,
        accountId: AccountId,
    ): Flow<ConsumerInfo?> {
        return subscribe(chainId) {
            metadata.resources.consumers.observe(accountId)
                .map { it?.toDomain(accountId) }
        }
    }

    override suspend fun resolveConsumers(
        chainId: ChainId,
        accountIds: Collection<AccountId>,
    ): Result<Map<AccountId, ConsumerInfo>> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.resources.consumers.entries(accountIds)
                .mapValues {
                    it.value.toDomain(it.key)
                }
        }
    }

    override suspend fun accountIdOfUsername(chainId: ChainId, input: String): Result<AccountId?> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.resources.usernameOwnerOf.query(input)
        }
    }

    override suspend fun usernameReservationQueue(chainId: ChainId, username: String): Result<List<UsernameReservation>> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.resources.usernameReservationQueue.query(username)
        }
            .map { entries ->
                entries.orEmpty().map { it.toDomain() }
            }
    }

    override suspend fun reservationDuration(chainId: ChainId): Result<Duration> {
        return remoteStorageSource.queryCatching(chainId) {
            metadata.resources.reservationDuration.queryNonNull()
        }
            .map {
                it.toLong().seconds
            }
    }

    override suspend fun consumerInfoOfUsername(
        chainId: ChainId,
        input: String,
    ): Result<ConsumerInfo?> {
        return accountIdOfUsername(chainId, input)
            .mapNotNull {
                consumerInfo(chainId, it)
                    .getOrNull()
            }
    }

    private fun OnChainConsumerInfo.toDomain(accountId: AccountId) = ConsumerInfo(
        accountId = accountId,
        identifierKey = identifierKey.toDomain().getOrThrow(),
        liteUsername = liteUsername,
        fullUsername = fullUsername
    )

    private fun OnChainReservationQueueEntry.toDomain() = UsernameReservation(account, joinedAt)
}
