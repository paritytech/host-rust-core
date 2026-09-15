package io.paritytech.polkadotapp.feature_videogame_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.scope.GlobalUpdaterScope
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_videogame_impl.data.personhoodThreshold
import io.paritytech.polkadotapp.feature_videogame_impl.data.score
import javax.inject.Inject

class PersonhoodScoreThresholdUpdater @Inject constructor(
    chainRegistry: ChainRegistry,
    storageCache: StorageCache
) : SingleStorageKeyUpdater<Unit>(GlobalUpdaterScope, chainRegistry, storageCache) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: Unit, chain: Chain): String {
        return withRuntime.runtime.metadata.score.personhoodThreshold.storageKey()
    }
}
