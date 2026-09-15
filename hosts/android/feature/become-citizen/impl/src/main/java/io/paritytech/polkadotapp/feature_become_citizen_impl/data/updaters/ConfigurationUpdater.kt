package io.paritytech.polkadotapp.feature_become_citizen_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.scope.GlobalUpdaterScope
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.configuration
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.proofOfInk
import javax.inject.Inject

class ConfigurationUpdater @Inject constructor(
    chainRegistry: ChainRegistry,
    storageCache: StorageCache
) : SingleStorageKeyUpdater<Unit>(
    scope = GlobalUpdaterScope,
    chainRegistry = chainRegistry,
    storageCache = storageCache
) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: Unit, chain: Chain): String {
        return withRuntime.runtime.metadata.proofOfInk.configuration.storageKey()
    }
}
