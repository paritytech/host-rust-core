package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.chains.di.LocalSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.api.observeNonNull
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.subscribeCatching
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobCredit
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

interface MobRuleVotingStatsRepository {
    fun mobCreditFlow(chainId: ChainId, alias: BandersnatchAlias): Flow<Result<MobCredit>>
}

class RealMobRuleVotingStatsRepository @Inject constructor(
    @LocalSourceQualifier private val localStorageDataSource: StorageDataSource,
) : MobRuleVotingStatsRepository {
    override fun mobCreditFlow(chainId: ChainId, alias: BandersnatchAlias): Flow<Result<MobCredit>> {
        return localStorageDataSource.subscribeCatching(chainId) {
            metadata.mobRule.credits.observeNonNull(alias)
        }
    }
}
