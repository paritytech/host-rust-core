package io.paritytech.polkadotapp.feature_people_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.MultipleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_account_api.data.CandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_people_api.data.AliasContextProvider
import io.paritytech.polkadotapp.feature_people_api.data.SetAliasContext
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.accountToAlias
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.people
import javax.inject.Inject

class PersonAliasesUpdater @Inject constructor(
    chainRegistry: ChainRegistry,
    @CandidateAccount scope: Updater.NoChainScope<MetaAccount>,
    storageCache: StorageCache,
    private val accountRepository: AccountRepository,
    @SetAliasContext private val assignableContexts: Set<@JvmSuppressWildcards AliasContextProvider>
) : MultipleStorageKeyUpdater<MetaAccount>(scope, chainRegistry, storageCache) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKeys(
        scopeValue: MetaAccount,
        chain: Chain
    ): List<String> = assignableContexts
        .map { provider ->
            accountRepository.getAliasAccount(provider.context()).accountIdIn(chain)
        }
        .map { accountId ->
            withRuntime.runtime.metadata.people.accountToAlias.storageKey(accountId)
        }
}
