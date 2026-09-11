package io.paritytech.polkadotapp.feature_coinage_impl.data.transaction

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.ChainEventsRepositoryFactory
import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.ExtrinsicOutcome
import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.getExtrinsicWithEvents
import io.paritytech.polkadotapp.chains.multiNetwork.runtime.repository.status
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.chains.network.binding.BlockNumber
import io.paritytech.polkadotapp.chains.network.rpc.RpcCalls
import io.paritytech.polkadotapp.chains.network.rpc.getBlockNumber
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.StorageKey4
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.chains.util.extrinsicHash
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.ensureKeysWithNullDefault
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageInstanceId
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.toRingCollectionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CheckpointBlock
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.coinage
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.coinsByOwner
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.recyclerAliasStates
import io.paritytech.polkadotapp.feature_coinage_impl.data.blockchain.recyclersCoinToRecycler
import io.paritytech.polkadotapp.feature_coinage_impl.data.config.CoinageInstanceIdProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainAliasState
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainCoinInfo
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogD
import io.paritytech.polkadotapp.feature_coinage_impl.domain.coinageLogW
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.shortHash
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transactions.api.domain.model.TransactionHash
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.math.BigInteger
import javax.inject.Inject

class RealCoinageChainViewFactory @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    @param:RemoteSourceQualifier private val remoteStorageSource: StorageDataSource,
    private val chainEventsRepositoryFactory: ChainEventsRepositoryFactory,
    private val rpcCalls: RpcCalls,
    private val membersRepository: MembersRepository,
    private val coinageInstanceIdProvider: CoinageInstanceIdProvider,
) : CoinageChainViewFactory {
    override suspend fun pin(): Result<CoinageChainView> = coinageInstanceIdProvider.instanceId().mapCatching { instanceId ->
        coroutineScope {
            val chainId = chainAssetProvider.chainId()

            val finalizedHash = rpcCalls.getFinalizedHead(chainId)
            val bestHash = rpcCalls.getBlockHash(chainId)

            val finalizedNumber = async { rpcCalls.getBlockNumber(chainId, finalizedHash).toLong() }
            val bestNumber = async { rpcCalls.getBlockNumber(chainId, bestHash).toLong() }

            RealCoinageChainView(
                chainId = chainId,
                instanceId = instanceId,
                finalizedHead = CheckpointBlock(finalizedNumber.await(), finalizedHash),
                bestHead = CheckpointBlock(bestNumber.await(), bestHash),
                remoteStorageSource = remoteStorageSource,
                chainEventsRepositoryFactory = chainEventsRepositoryFactory,
                rpcCalls = rpcCalls,
                membersRepository = membersRepository,
            )
        }
    }.onFailure {
        // A failed pin aborts a whole recovery pass before anything else can be logged about it.
        coinageLogW("chain-view-pin-failed error=$it")
    }

    override fun finalizedHeads(): Flow<BlockNumber> = flowOfAll {
        rpcCalls.subscribeFinalizedHeads(chainAssetProvider.chainId())
    }.map { BlockNumber(it.number.toBigInteger()) }

    override fun bestHeads(): Flow<BlockNumber> = flowOfAll {
        rpcCalls.subscribeNewHeads(chainAssetProvider.chainId())
    }.map { BlockNumber(it.number.toBigInteger()) }
}

private class RealCoinageChainView(
    private val chainId: ChainId,
    private val instanceId: CoinageInstanceId,
    override val finalizedHead: CheckpointBlock,
    override val bestHead: CheckpointBlock,
    private val remoteStorageSource: StorageDataSource,
    private val chainEventsRepositoryFactory: ChainEventsRepositoryFactory,
    private val rpcCalls: RpcCalls,
    private val membersRepository: MembersRepository,
) : CoinageChainView {
    override suspend fun coinsAt(at: BlockHash, coins: List<AccountId>): Result<Map<AccountId, OnChainCoinInfo?>> {
        if (coins.isEmpty()) return Result.success(emptyMap())

        return remoteStorageSource.queryCatching(chainId, at = at) {
            metadata.coinage.coinsByOwner.entries(coins)
        }.map { it.ensureKeysWithNullDefault(coins) }
    }

    override suspend fun recyclerMembershipsAt(
        at: BlockHash,
        memberKeys: List<BandersnatchPublicKey>,
    ): Result<Map<BandersnatchPublicKey, ValueExponent?>> {
        if (memberKeys.isEmpty()) return Result.success(emptyMap())

        return remoteStorageSource.queryCatching(chainId, at = at) {
            metadata.coinage.recyclersCoinToRecycler.entries(memberKeys)
        }.map { locations ->
            locations
                .filterValues { location -> location.instanceId.toUInt() == instanceId }
                .mapValues { (_, location) -> ValueExponent(location.value) }
                .ensureKeysWithNullDefault(memberKeys)
        }
    }

    override suspend fun ringPositionsAt(
        at: BlockHash,
        memberships: Map<BandersnatchPublicKey, ValueExponent>,
    ): Result<Map<BandersnatchPublicKey, RingPosition?>> {
        if (memberships.isEmpty()) return Result.success(emptyMap())

        val keys = memberships.map { (member, denomination) -> denomination.toRingCollectionId(instanceId) to member }

        return membersRepository.fetchMembers(
            chainId = chainId,
            keys = keys,
            consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
            blockHash = at,
        ).map { positions ->
            positions.mapKeys { (key, _) -> key.second }.ensureKeysWithNullDefault(memberships.keys)
        }
    }

    override suspend fun aliasStatesAt(
        at: BlockHash,
        keys: List<RecyclerAliasKey>,
    ): Result<Map<RecyclerAliasKey, OnChainAliasState?>> {
        if (keys.isEmpty()) return Result.success(emptyMap())

        val instanceIdKey = instanceId.toLong().toBigInteger()
        val storageKeys = keys.map { StorageKey4(instanceIdKey, it.valueExponent, it.recyclerIndex, it.alias.value) }

        return remoteStorageSource.queryCatching(chainId, at = at) {
            metadata.coinage.recyclerAliasStates.entries(storageKeys)
        }.map { states ->
            states.mapKeys { (key, _) -> RecyclerAliasKey(key.second, key.third, key.fourth.toDataByteArray()) }
                .ensureKeysWithNullDefault(keys)
        }
    }

    override suspend fun blockHashAt(blockNumber: Long): Result<BlockHash?> = runCatching {
        rpcCalls.getBlockHash(chainId, BlockNumber(BigInteger.valueOf(blockNumber)))
    }

    override suspend fun blockNumberAt(hash: BlockHash): Result<Long?> = runCatching {
        rpcCalls.getBlockNumber(chainId, hash).toLong()
    }

    override suspend fun dispatchOutcomeAt(at: BlockHash, txHash: TransactionHash): Result<ExtrinsicOutcome?> =
        runCatching {
            chainEventsRepositoryFactory.create(chainId)
                .getExtrinsicWithEvents(txHash, at)
                ?.status()
        }

    override suspend fun getAppliedExtrinsicHashes(at: BlockHash): Result<List<TransactionHash>> = runCatching {
        rpcCalls.getBlock(chainId, at).block.extrinsics.map { it.extrinsicHash() }
    }

    override suspend fun searchForTransaction(
        fromBlockNumber: Long,
        toBlockNumber: Long,
        txHash: TransactionHash,
    ): TransactionSearchResult = searchRange(fromBlockNumber, toBlockNumber, txHash)
}

/**
 * Walks `[fromBlockNumber … toBlockNumber]` looking for [txHash], reading the block hashes and bodies concurrently.
 *
 * An unreadable block only clears [TransactionSearchResult.NotFound.wholeRangeRead] — the search keeps
 * going, because a hit is positive evidence regardless of what could not be read on the way, while a miss
 * only means something if every block was actually looked at.
 */
internal suspend fun CoinageChainView.searchRange(
    fromBlockNumber: Long,
    toBlockNumber: Long,
    txHash: TransactionHash,
): TransactionSearchResult = coroutineScope {
    val blocks = (fromBlockNumber..toBlockNumber).map { number ->
        number to async {
            val hash = blockHashAt(number).getOrNull()
            hash to hash?.let { getAppliedExtrinsicHashes(it).getOrNull() }
        }
    }

    var unreadableBlocks = 0

    for ((number, deferred) in blocks) {
        val (hash, body) = deferred.await()

        if (hash == null || body == null) {
            unreadableBlocks++
            continue
        }

        if (txHash !in body) continue

        // The body is already in hand, so the outcome costs one further read of that block's events.
        val outcome = dispatchOutcomeAt(hash, txHash).getOrNull()

        coinageLogD("tx-search found tx=${txHash.shortHash()} block=$number outcome=$outcome unreadable=$unreadableBlocks")

        return@coroutineScope TransactionSearchResult.Found(CheckpointBlock(number, hash), outcome)
    }

    if (unreadableBlocks > 0) {
        coinageLogW(
            "tx-search absence-inconclusive tx=${txHash.shortHash()} " +
                "range=$fromBlockNumber..$toBlockNumber unreadable=$unreadableBlocks"
        )
    } else {
        coinageLogD("tx-search absent tx=${txHash.shortHash()} range=$fromBlockNumber..$toBlockNumber")
    }

    TransactionSearchResult.NotFound(wholeRangeRead = unreadableBlocks == 0)
}
