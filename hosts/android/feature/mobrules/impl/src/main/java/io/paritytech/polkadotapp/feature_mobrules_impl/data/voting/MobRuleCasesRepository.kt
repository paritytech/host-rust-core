package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting

import io.paritytech.polkadotapp.chains.call.MultiChainRuntimeCallsApi
import io.paritytech.polkadotapp.chains.di.RemoteSourceQualifier
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.chains.storage.source.*
import io.paritytech.polkadotapp.chains.storage.source.query.StorageQueryContext
import io.paritytech.polkadotapp.chains.storage.source.query.metadata
import io.paritytech.polkadotapp.common.utils.filterNotNull
import io.paritytech.polkadotapp.common.utils.orZero
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleDoneCase
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleOpenCase
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import java.math.BigInteger
import javax.inject.Inject

data class CaseObservation(
    val caseId: MobRuleCaseId,
    val doneCase: MobRuleDoneCase?,
    val openCase: MobRuleOpenCase?,
    val ripeCase: MobRuleOpenCase?
)

interface MobRuleCasesRepository {
    fun casesCountFlow(chainId: ChainId): Flow<Result<BigInteger>>

    suspend fun getVotedCases(chainId: ChainId, alias: PersonalAlias): Result<List<MobRuleCaseId>>

    suspend fun openCases(chainId: ChainId): Result<Map<MobRuleCaseId, MobRuleOpenCase>>

    suspend fun observeCaseUpdates(chainId: ChainId, caseIds: List<MobRuleCaseId>): Flow<CaseObservation>
}

class RealMobRuleCasesRepository @Inject constructor(
    @RemoteSourceQualifier private val remoteStorageDataSource: StorageDataSource,
    private val multiChainRuntimeCallsApi: MultiChainRuntimeCallsApi,
) : MobRuleCasesRepository {
    override fun casesCountFlow(chainId: ChainId): Flow<Result<BigInteger>> {
        return remoteStorageDataSource.subscribeCatching(chainId) {
            metadata.mobRule.caseCount.observe().map { it.orZero() }
        }
    }

    override suspend fun getVotedCases(chainId: ChainId, alias: PersonalAlias): Result<List<MobRuleCaseId>> {
        return runCatching {
            val runtimeApi = multiChainRuntimeCallsApi.forChain(chainId)
            runtimeApi.mobRule.votedOn(alias, doneOnly = false)
        }
    }

    override suspend fun openCases(chainId: ChainId): Result<Map<MobRuleCaseId, MobRuleOpenCase>> {
        return remoteStorageDataSource.queryCatching(chainId) {
            metadata.mobRule.openCases.entries()
                .filterNotNull()
        }
    }

    override suspend fun observeCaseUpdates(
        chainId: ChainId,
        caseIds: List<MobRuleCaseId>
    ): Flow<CaseObservation> {
        return remoteStorageDataSource.subscribeBatched(chainId) {
            caseIds.map { caseId ->
                observeCase(caseId)
            }.merge()
        }
    }
}

private fun StorageQueryContext.observeCase(caseId: MobRuleCaseId): Flow<CaseObservation> {
    return combine(
        metadata.mobRule.doneCases.observe(caseId),
        metadata.mobRule.openCases.observe(caseId),
        metadata.mobRule.ripeCases.observe(caseId)
    ) { done, open, ripe -> CaseObservation(caseId, done, open, ripe) }
}
