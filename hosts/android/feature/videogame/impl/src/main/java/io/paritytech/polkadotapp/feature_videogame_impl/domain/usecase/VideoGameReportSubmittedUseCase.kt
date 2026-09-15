package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalCache
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.memory.useSharedFlow
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeOurPlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

internal interface VideoGameReportSubmittedUseCase {
    context(scope: ComputationalScope)
    fun observeReportSubmitted(): Flow<Boolean>
}

internal class RealVideoGameReportSubmittedUseCase @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val gameRepository: VideoGameRepositoryInternal,
    private val computationalCache: ComputationalCache,
    private val scoreContextProvider: ScoreContextProvider,
) : VideoGameReportSubmittedUseCase {
    companion object {
        private const val REPORT_SUBMITTED_CACHE_KEY = "RealVideoGameReportSubmittedUseCase.ReportSubmitted"
    }

    context(scope: ComputationalScope)
    override fun observeReportSubmitted(): Flow<Boolean> = computationalCache
        .useSharedFlow(REPORT_SUBMITTED_CACHE_KEY) {
            val chain = chainRegistry.peopleChain()
            val candidateAccount = accountRepository.getCandidateAccount()
            val playerAccountId = candidateAccount.accountIdIn(chain)
            val scoreAlias = bandersnatchSecretsStorage.getAliasInContext(candidateAccount.id, scoreContextProvider.context())

            gameRepository.subscribeOurPlayer(chain.id, playerAccountId, scoreAlias)
                .map { it?.data?.sentReport == true }
        }
}
