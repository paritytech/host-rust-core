package io.paritytech.polkadotapp.feature_mobrules_impl.data.credits.claimVotes

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.call.MultiChainRuntimeCallsApi
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_mobrules_impl.data.credits.MobRuleCreditsSyncWorker
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.claimVotes
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.mobRule
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.votedOn
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import timber.log.Timber
import javax.inject.Inject

class ClaimVotesExecutor @Inject constructor(
    private val accountRepository: AccountRepository,
    private val multiChainRuntimeCallsApi: MultiChainRuntimeCallsApi,
    private val extrinsicService: ExtrinsicService,
    private val peopleOrigins: PeopleOrigins,
    private val knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
) : MobRuleCreditsSyncWorker.SyncExecutor {
    override suspend fun executeSync(): Result<Unit> {
        return runCatching {
            val alias = accountRepository.getCandidateAlias(BandersnatchContext.MOB_RULE)
            multiChainRuntimeCallsApi.forChain(knownChains.people).mobRule.votedOn(alias, doneOnly = true)
        }.flatMap { doneVotes ->
            if (doneVotes.isEmpty()) {
                Timber.d("No done votes to claim found, skipping")
                return@flatMap Result.success(Unit)
            }

            Timber.d("${doneVotes.size} done cases to claim found, claiming")

            val chain = chainRegistry.getChain(knownChains.people)
            peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(BandersnatchContext.MOB_RULE).flatMap { transactionOrigin ->
                extrinsicService.submitExtrinsicAndAwaitExecution(
                    chain = chain,
                    origin = transactionOrigin
                ) {
                    mobRule.claimVotes(doneVotes)
                }
                    .flattenExecutionFailure()
                    .coerceToUnit()
            }
        }
    }
}
