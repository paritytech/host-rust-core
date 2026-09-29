package io.paritytech.polkadotapp.feature_chain_resources_api.data.repository

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.util.addressOf
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.requireNotNull
import io.paritytech.polkadotapp.feature_chain_resources_api.domain.model.ConsumerInfo
import io.paritytech.polkadotapp.feature_chain_resources_api.domain.model.UsernameReservation
import kotlinx.coroutines.flow.Flow
import timber.log.Timber
import kotlin.time.Duration

interface ResourcesRepository {
    suspend fun consumerInfo(
        chainId: ChainId,
        accountId: AccountId,
    ): Result<ConsumerInfo?>

    suspend fun consumerInfoLocal(
        chainId: ChainId,
        accountId: AccountId,
    ): Result<ConsumerInfo?>

    fun consumerInfoFlow(
        chainId: ChainId,
        accountId: AccountId,
    ): Flow<ConsumerInfo?>

    fun consumerInfoLocalFlow(
        chainId: ChainId,
        accountId: AccountId,
    ): Flow<ConsumerInfo?>

    suspend fun resolveConsumers(
        chainId: ChainId,
        accountIds: Collection<AccountId>,
    ): Result<Map<AccountId, ConsumerInfo>>

    suspend fun accountIdOfUsername(
        chainId: ChainId,
        input: String,
    ): Result<AccountId?>

    suspend fun usernameReservationQueue(
        chainId: ChainId,
        username: String
    ): Result<List<UsernameReservation>>

    suspend fun reservationDuration(
        chainId: ChainId,
    ): Result<Duration>

    suspend fun consumerInfoOfUsername(
        chainId: ChainId,
        input: String,
    ): Result<ConsumerInfo?>
}

suspend fun ResourcesRepository.requireConsumerInfo(
    chain: Chain,
    accountId: AccountId,
): Result<ConsumerInfo> {
    return consumerInfo(chain.id, accountId)
        .requireNotNull {
            val errorMsg = "Account ${chain.addressOf(accountId)} does not have consumer info registered on-chain"
            Timber.d(errorMsg)
            IllegalStateException(errorMsg)
        }
}
