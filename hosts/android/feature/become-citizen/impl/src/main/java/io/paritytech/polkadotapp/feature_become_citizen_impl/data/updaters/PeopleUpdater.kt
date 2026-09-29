package io.paritytech.polkadotapp.feature_become_citizen_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.people
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.proofOfInk
import io.paritytech.polkadotapp.feature_people_api.data.updaters.scope.PersonIdScope
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import javax.inject.Inject

class PeopleUpdater @Inject constructor(
    scope: PersonIdScope,
    chainRegistry: ChainRegistry,
    storageCache: StorageCache,
) : SingleStorageKeyUpdater<PersonId?>(
    scope = scope,
    chainRegistry = chainRegistry,
    storageCache = storageCache
) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: PersonId?, chain: Chain): String? {
        if (scopeValue == null) return null

        return withRuntime.runtime.metadata.proofOfInk.people.storageKey(scopeValue)
    }
}
