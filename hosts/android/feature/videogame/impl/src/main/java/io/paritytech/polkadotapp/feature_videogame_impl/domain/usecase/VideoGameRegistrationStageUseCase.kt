package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.withAmount
import io.paritytech.polkadotapp.common.data.memory.ComputationalCache
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.memory.useSharedFlow
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.withFlowScope
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_balances_api.data.repository.BalanceRepository
import io.paritytech.polkadotapp.feature_balances_api.domain.model.TokenBalance
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.CandidateDepositAssetProvider
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainParticipant
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePlayerInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameRecognition
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.canRegisterWithoutProvingCredibility
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.isRegistered
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ScoreRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeAccountPlayer
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeOurParticipant
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribePersonPlayer
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface VideoGameRegistrationStageUseCase {
    context(scope: ComputationalScope)
    fun subscribe(): Flow<VideoGameRegistrationStage>

    context(scope: ComputationalScope)
    suspend fun get(): VideoGameRegistrationStage
}

class RealVideoGameRegistrationStageUseCase @Inject constructor(
    private val accountRepository: AccountRepository,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val scoreRepository: ScoreRepository,
    private val balanceRepository: BalanceRepository,
    private val computationalCache: ComputationalCache,
    private val personStatusUseCase: PersonStatusUseCase,
    private val gameInvitationUseCase: GameInvitationUseCase,
    @param:CandidateDepositAssetProvider private val assetProvider: ChainAssetProvider,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val scoreContextProvider: ScoreContextProvider
) : VideoGameRegistrationStageUseCase {
    companion object {
        private const val GAME_REGISTRATION_STAGE_CACHE_KEY = "11a97355-42ee-49ce-b859-67f70695dd82"
    }

    context(scope: ComputationalScope)
    override fun subscribe(): Flow<VideoGameRegistrationStage> = computationalCache
        .useSharedFlow(GAME_REGISTRATION_STAGE_CACHE_KEY) {
            withFlowScope {
                val (chain, asset) = assetProvider()
                val account = accountRepository.getCandidateAccount()
                val accountId = account.accountIdIn(chain)
                val scoreAlias = bandersnatchSecretsStorage.getAliasInContext(account.id, scoreContextProvider.context())

                combine(
                    scoreRepository.subscribeOurParticipant(chain.id, accountId, scoreAlias),
                    personStatusUseCase.personhoodAccountsFullySetFlow(),
                    ::isExternallyRecognized
                )
                    .distinctUntilChanged()
                    .flatMapLatest { externallyRecognized ->
                        if (externallyRecognized) {
                            createFlowForExternallyRecognized(chain, scoreAlias)
                        } else {
                            createFlowForGameRecognized(chain, asset, accountId, account)
                        }
                    }.distinctUntilChanged()
            }
        }

    context(scope: ComputationalScope)
    override suspend fun get(): VideoGameRegistrationStage {
        return subscribe().first()
    }

    private fun createFlowForExternallyRecognized(
        chain: Chain,
        scoreAlias: PersonalAlias
    ): Flow<VideoGameRegistrationStage> {
        return videoGameRepository
            .subscribePersonPlayer(chain.id, scoreAlias)
            .map(::stageForExternallyRecognized)
    }

    private fun isExternallyRecognized(
        scoreParticipant: OnChainParticipant?,
        isAlreadyPerson: Boolean
    ): Boolean = when (scoreParticipant) {
        null -> isAlreadyPerson
        else -> scoreParticipant.recognition is OnChainVideoGameRecognition.ExternallyRecognized
    }

    context(scope: ComputationalScope)
    private fun createFlowForGameRecognized(
        chain: Chain,
        asset: Chain.Asset,
        accountId: AccountId,
        account: MetaAccount
    ): Flow<VideoGameRegistrationStage> {
        val getDeposit = scope.async(start = CoroutineStart.LAZY) {
            asset.withAmount(videoGameRepository.getRegistrationRequiredAmount(chain, asset))
        }

        return combine(
            videoGameRepository.subscribeAccountPlayer(chain.id, accountId),
            balanceRepository.syncedTokenBalanceFlow(account.id, asset),
            gameInvitationUseCase.activeGameInvitationFlow()
        ) { playerInfo, tokenBalance, issuedInvitation ->
            stageForGameRecognized(playerInfo, tokenBalance, issuedInvitation, getDeposit)
        }
    }

    private fun stageForExternallyRecognized(playerInfo: OnChainVideoGamePlayerInfo?): VideoGameRegistrationStage {
        return if (playerInfo?.registered == true) {
            VideoGameRegistrationStage.Registered
        } else {
            VideoGameRegistrationStage.CanRegister.NoCredibilityProofRequired(externallyRecognized = true)
        }
    }

    private suspend fun stageForGameRecognized(
        playerInfo: OnChainVideoGamePlayerInfo?,
        tokenBalance: TokenBalance,
        issuedInvitation: IssuedInvitation?,
        depositAsync: Deferred<ChainAssetWithAmount>
    ): VideoGameRegistrationStage {
        if (playerInfo.isRegistered()) return VideoGameRegistrationStage.Registered
        if (playerInfo.canRegisterWithoutProvingCredibility()) return VideoGameRegistrationStage.CanRegister.NoCredibilityProofRequired(externallyRecognized = false)

        val requiredDeposit = depositAsync.await()
        return when {
            issuedInvitation != null || canPayDeposit(requiredDeposit, tokenBalance) ->
                VideoGameRegistrationStage.CanRegister.WithCredibilityProof(
                    requiredDeposit = requiredDeposit,
                    cachedInvite = issuedInvitation,
                )

            else -> VideoGameRegistrationStage.NeedsCredibilityProof(requiredDeposit)
        }
    }

    private fun canPayDeposit(deposit: ChainAssetWithAmount, balance: TokenBalance): Boolean {
        return balance.canReserve(deposit.amount)
    }
}
