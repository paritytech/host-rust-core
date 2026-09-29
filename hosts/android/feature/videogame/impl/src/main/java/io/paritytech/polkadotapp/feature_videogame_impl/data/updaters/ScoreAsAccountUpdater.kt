package io.paritytech.polkadotapp.feature_videogame_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_account_api.data.CandidateAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.participants
import io.paritytech.polkadotapp.feature_videogame_impl.data.score
import javax.inject.Inject

class ScoreAsAccountUpdater @Inject constructor(
    @CandidateAccount scope: Updater.NoChainScope<MetaAccount>,
    chainRegistry: ChainRegistry,
    storageCache: StorageCache
) : SingleStorageKeyUpdater<MetaAccount>(scope, chainRegistry, storageCache) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: MetaAccount, chain: Chain): String {
        val currentAccountId = scopeValue.accountIdIn(chain)

        return withRuntime.runtime.metadata.score
            .participants
            .storageKey(OnChainAccountOrPerson.Account(currentAccountId))
    }
}
