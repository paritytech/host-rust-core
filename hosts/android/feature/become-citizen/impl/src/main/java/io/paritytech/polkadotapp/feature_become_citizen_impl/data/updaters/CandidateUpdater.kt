package io.paritytech.polkadotapp.feature_become_citizen_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.candidates
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api.proofOfInk
import javax.inject.Inject

class CandidateUpdater @Inject constructor(
    override val scope: Updater.NoChainScope<MetaAccount>,
    chainRegistry: ChainRegistry,
    storageCache: StorageCache
) : SingleStorageKeyUpdater<MetaAccount>(
    scope = scope,
    chainRegistry = chainRegistry,
    storageCache = storageCache
) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: MetaAccount, chain: Chain): String {
        return withRuntime.runtime.metadata.proofOfInk.candidates.storageKey(scopeValue.accountIdIn(chain).value)
    }
}
