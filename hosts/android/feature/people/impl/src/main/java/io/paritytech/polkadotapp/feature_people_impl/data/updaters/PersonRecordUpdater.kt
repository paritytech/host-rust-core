package io.paritytech.polkadotapp.feature_people_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_people_api.data.updaters.scope.PersonIdScope
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.people
import javax.inject.Inject

class PersonRecordUpdater @Inject constructor(
    scope: PersonIdScope,
    chainRegistry: ChainRegistry,
    storageCache: StorageCache,
) : SingleStorageKeyUpdater<PersonId?>(
    scope = scope,
    chainRegistry = chainRegistry,
    storageCache = storageCache
) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(
        scopeValue: PersonId?,
        chain: Chain
    ): String? {
        if (scopeValue == null) return null

        return withRuntime.runtime.metadata.people.people.storageKey(scopeValue)
    }
}
