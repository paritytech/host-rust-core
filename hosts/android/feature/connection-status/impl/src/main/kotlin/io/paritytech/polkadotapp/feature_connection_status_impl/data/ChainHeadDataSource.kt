package io.paritytech.polkadotapp.feature_connection_status_impl.data

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.network.rpc.RpcCalls
import io.paritytech.polkadotapp.common.utils.flowOfAll
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Best and finalized block-number streams per chain. `flowOfAll` re-subscribes the suspend head
 * subscription on collection; the underlying substrate-sdk subscription itself survives reconnects.
 */
@Singleton
class ChainHeadDataSource @Inject constructor(
    private val rpcCalls: RpcCalls,
) {
    fun bestBlockNumber(chainId: ChainId): Flow<Int> =
        flowOfAll { rpcCalls.subscribeNewHeads(chainId) }.map { it.number }

    fun finalizedBlockNumber(chainId: ChainId): Flow<Int> =
        flowOfAll { rpcCalls.subscribeFinalizedHeads(chainId) }.map { it.number }
}
