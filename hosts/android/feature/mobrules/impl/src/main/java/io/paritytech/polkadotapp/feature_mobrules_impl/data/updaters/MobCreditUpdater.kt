package io.paritytech.polkadotapp.feature_mobrules_impl.data.updaters

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.updaters.SingleStorageKeyUpdater
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.storage.StorageCache
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_account_api.data.CandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.credits
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.mobRule
import javax.inject.Inject

class MobCreditUpdater @Inject constructor(
    @CandidateAccount scope: Updater.NoChainScope<MetaAccount>,
    chainRegistry: ChainRegistry,
    storageCache: StorageCache,
    private val accountRepository: AccountRepository,
) : SingleStorageKeyUpdater<MetaAccount>(
    scope = scope,
    chainRegistry = chainRegistry,
    storageCache = storageCache
) {
    context(withRuntime: WithRuntime)
    override suspend fun storageKey(scopeValue: MetaAccount, chain: Chain): String? {
        val alias = accountRepository.getCandidateAlias(BandersnatchContext.MOB_RULE)
        return withRuntime.runtime.metadata.mobRule.credits.storageKey(alias)
    }
}
