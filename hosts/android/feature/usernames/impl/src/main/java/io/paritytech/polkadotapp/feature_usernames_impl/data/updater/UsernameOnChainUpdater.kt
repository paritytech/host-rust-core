package io.paritytech.polkadotapp.feature_usernames_impl.data.updater

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_chain_resources_api.data.api.consumers
import io.paritytech.polkadotapp.feature_chain_resources_api.data.api.resources

// TODO: People Chain is used until dotNS resolve-by-address lands (paritytech/dotns#216, #217)
class UsernameOnChainUpdater(
    chainRegistry: ChainRegistry,
    storageCache: StorageCache,
    scope: Updater.NoChainScope<MetaAccount>
) : SingleStorageKeyUpdater<MetaAccount>(scope, chainRegistry, storageCache) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: MetaAccount, chain: Chain): String {
        val accountId = scopeValue.accountIdIn(chain)

        return withRuntime.runtime.metadata.resources.consumers.storageKey(accountId)
    }
}
