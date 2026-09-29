package io.paritytech.polkadotapp.chains.storage.source

import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.wsrpc.executeAsync
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.getSocket
import io.paritytech.polkadotapp.chains.multiNetwork.requests.StorageSharedRequestsBuilderFactory
import io.paritytech.polkadotapp.chains.multiNetwork.requests.SubstrateSubscriptionBuilder
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.chains.network.rpc.requests.GetChildStateRequest
import io.paritytech.polkadotapp.chains.storage.source.query.RemoteStorageQueryContextFactory
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.intercept.InterceptingStorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.intercept.StorageInterceptorRegistry
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers

internal class RemoteStorageSource(
    chainRegistry: ChainRegistry,
    sharedRequestsBuilderFactory: StorageSharedRequestsBuilderFactory,
    private val remoteStorageQueryContextFactory: RemoteStorageQueryContextFactory,
    coroutineDispatchers: CoroutineDispatchers,
    private val interceptorRegistry: StorageInterceptorRegistry,
) : BaseStorageSource(chainRegistry, sharedRequestsBuilderFactory, coroutineDispatchers) {
    override suspend fun queryChildState(
        storageKey: String,
        childKey: String,
        chainId: String,
    ): String? {
        val response = getSocketService(chainId).executeAsync(GetChildStateRequest(storageKey, childKey))

        return response.result as? String?
    }

    override suspend fun createQueryContext(
        chainId: String,
        at: BlockHash?,
        runtime: RuntimeSnapshot,
        subscriptionBuilder: SubstrateSubscriptionBuilder?,
    ): StorageQueryContext {
        return InterceptingStorageQueryContext(
            delegate = remoteStorageQueryContextFactory.create(
                chainId = chainId,
                subscriptionBuilder = subscriptionBuilder,
                at = at
            ),
            registry = interceptorRegistry,
        )
    }

    private suspend fun getSocketService(chainId: String) = chainRegistry.getSocket(chainId)
}
