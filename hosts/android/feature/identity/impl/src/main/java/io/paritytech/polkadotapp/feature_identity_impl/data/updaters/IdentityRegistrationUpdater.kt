package io.paritytech.polkadotapp.feature_identity_impl.data.updaters

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_identity_impl.data.IDENTITY
import io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain.identity
import io.paritytech.polkadotapp.feature_identity_impl.data.network.blockchain.identityOf
import javax.inject.Inject

class IdentityRegistrationUpdater @Inject constructor(
    scope: Updater.NoChainScope<MetaAccount>,
    chainRegistry: ChainRegistry,
    storageCache: StorageCache,
    private val accountRepository: AccountRepository
) : SingleStorageKeyUpdater<MetaAccount>(scope, chainRegistry, storageCache) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: MetaAccount, chain: Chain): String {
        val identityAccount = accountRepository.getAliasAccount(BandersnatchContext.IDENTITY)
        return withRuntime.runtime.metadata.identity.identityOf.storageKey(identityAccount.accountIdIn(chain))
    }
}
