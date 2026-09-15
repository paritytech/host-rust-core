package io.paritytech.polkadotapp.feature_mobrules_impl.data.credits.claimCredit

import io.novasama.substrate_sdk_android.hash.isPositive
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.chains.storage.source.queryCatching
import io.paritytech.polkadotapp.common.utils.coerceToUnit
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.orZero
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_mobrules_impl.data.credits.MobRuleCreditsSyncWorker
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.claimCredit
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.mobRule
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.payoutDistribution
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.votingPoints
import io.paritytech.polkadotapp.feature_people_api.data.signer.origins.PeopleOrigins
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.feature_transactions.api.data.flattenExecutionFailure
import timber.log.Timber
import javax.inject.Inject

class ClaimCreditExecutor @Inject constructor(
    private val accountRepository: AccountRepository,
    @RemoteSourceQualifier private val storageDataSource: StorageDataSource,
    private val extrinsicService: ExtrinsicService,
    private val peopleOrigins: PeopleOrigins,
    private val knownChains: KnownChains,
    private val chainRegistry: ChainRegistry,
) : MobRuleCreditsSyncWorker.SyncExecutor {
    override suspend fun executeSync(): Result<Unit> {
        return checkShouldClaimCredit().flatMap { shouldClaimCredit ->
            if (!shouldClaimCredit) {
                Timber.d("No credit to claim, skipping")
                return@flatMap Result.success(Unit)
            }

            Timber.d("Found credit to claim, claiming")

            val chain = chainRegistry.getChain(knownChains.people)
            peopleOrigins.asPersonalAliasWithAccountEnsuringRevision(BandersnatchContext.MOB_RULE).flatMap { origin ->
                extrinsicService.submitExtrinsicAndAwaitExecution(
                    chain = chain,
                    origin = origin
                ) {
                    mobRule.claimCredit()
                }
                    .flattenExecutionFailure()
                    .coerceToUnit()
            }
        }
    }

    private suspend fun checkShouldClaimCredit(): Result<Boolean> {
        return storageDataSource.queryCatching(knownChains.people) {
            val alias = accountRepository.getCandidateAlias(BandersnatchContext.MOB_RULE)

            val payoutDistribution = metadata.mobRule.payoutDistribution.query() ?: return@queryCatching false
            val votingPoints = metadata.mobRule.votingPoints.query(payoutDistribution.round, alias)?.value.orZero()

            votingPoints.isPositive()
        }
    }
}
