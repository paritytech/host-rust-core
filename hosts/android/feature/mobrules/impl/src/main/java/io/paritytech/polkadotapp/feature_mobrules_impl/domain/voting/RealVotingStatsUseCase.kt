package io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.chains.util.utilityAsset
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.common.utils.mapResult
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_mobrules_api.domain.model.VotingStats
import io.paritytech.polkadotapp.feature_mobrules_api.domain.model.intoVotingPoints
import io.paritytech.polkadotapp.feature_mobrules_api.domain.voting.VotingStatsUseCase
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.MobRuleVotingStatsRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class RealVotingStatsUseCase @Inject constructor(
    private val accountRepository: AccountRepository,
    private val chainRegistry: ChainRegistry,
    private val votingStatsRepository: MobRuleVotingStatsRepository,
) : VotingStatsUseCase {
    override fun currentVotingStatsFlow(): Flow<Result<VotingStats>> {
        return flowOfAll {
            val alias = accountRepository.getCandidateAlias(BandersnatchContext.MOB_RULE)
            val chain = chainRegistry.peopleChain()

            votingStatsRepository.mobCreditFlow(chain.id, alias).mapResult { mobCredit ->
                VotingStats(
                    totalScore = mobCredit.correct.intoVotingPoints(),
                    pendingRewards = chain.utilityAsset.withAmount(mobCredit.credit),
                )
            }
        }
    }
}
