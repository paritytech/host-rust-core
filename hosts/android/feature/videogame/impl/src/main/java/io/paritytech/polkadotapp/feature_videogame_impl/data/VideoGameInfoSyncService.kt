package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.network.binding.BlockHash
import io.paritytech.polkadotapp.common.data.memory.ComputationalCache
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.memory.useSharedFlow
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.common.utils.getOrEmpty
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.AccountOrPersonData
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRound
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState.Broken
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState.Cancelling
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState.InProgress
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState.Missed
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState.Processing
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState.Registration
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState.Shuffle
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePlayerInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePlayerRoundKey
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.isRegistered
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeOurPlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import javax.inject.Inject

interface VideoGameInfoSyncService {
    context(scope: ComputationalScope)
    fun subscribeCurrentActiveGameInfo(): Flow<VideoGameInfo?>
}

context(scope: ComputationalScope)
suspend fun VideoGameInfoSyncService.getCurrentActiveGameInfo(): VideoGameInfo {
    return subscribeCurrentActiveGameInfo().filterNotNull().first()
}

class RealVideoGameInfoSyncService @Inject constructor(
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val accountRepository: AccountRepository,
    private val chainRegistry: ChainRegistry,
    private val knownChains: KnownChains,
    private val computationalCache: ComputationalCache,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val scoreContextProvider: ScoreContextProvider
) : VideoGameInfoSyncService {
    companion object {
        private const val CACHE_KEY = "VideoGameInfoSyncService:CurrentActiveGameInfo"
    }

    private suspend fun peopleChain() = chainRegistry.getChain(knownChains.people)

    context(scope: ComputationalScope)
    override fun subscribeCurrentActiveGameInfo(): Flow<VideoGameInfo?> = computationalCache
        .useSharedFlow(CACHE_KEY) { cachingScope ->
            with(cachingScope) {
                subscribeCurrentActiveGameInfoInternal()
            }
        }

    context(scope: ComputationalScope)
    private fun subscribeCurrentActiveGameInfoInternal(): Flow<VideoGameInfo?> = flowOfAll {
        val chain = peopleChain()
        val candidateAccount = accountRepository.getCandidateAccount()
        val candidateAccountId = candidateAccount.accountIdIn(chain)
        val scoreAlias = bandersnatchSecretsStorage.getAliasInContext(candidateAccount.id, scoreContextProvider.context())

        combine(
            videoGameRepository.subscribeGameInfoAtBlock(chain.id),
            videoGameRepository.subscribeOurPlayer(chain.id, candidateAccountId, scoreAlias)
        ) { onChainGameInfoWithRaw, onChainPlayerInfoData ->
            val blockHash = onChainGameInfoWithRaw.at
            val onChainGameInfo = onChainGameInfoWithRaw.value

            val onChainPlayerInfo = onChainPlayerInfoData?.data

            onChainGameInfo?.let {
                val state = if (onChainPlayerInfo.isRegistered()) {
                    createRegisteredPlayerGameState(blockHash, it, onChainPlayerInfoData)
                } else {
                    createNonRegisteredPlayerGameState(it)
                }

                VideoGameInfo(
                    index = it.index,
                    registrationEnd = it.registrationEnds.toMillis(),
                    gameStartMillis = it.gameDate.toMillis(),
                    reportEnd = it.reportEnds.toMillis(),
                    rounds = it.rounds,
                    preferredMaxGroupSize = it.maxGroupSize,
                    state = state,
                    airdropScheduled = it.airdropScheduled,
                )
            }
        }
    }

    private suspend fun createRegisteredPlayerGameState(
        blockHash: BlockHash?,
        game: OnChainVideoGameInfo,
        currentPlayerData: AccountOrPersonData<OnChainVideoGamePlayerInfo>,
    ) = when (game.state) {
        is OnChainVideoGameState.Registration -> Registration
        is OnChainVideoGameState.Shuffle -> Shuffle
        is OnChainVideoGameState.Reporting -> {
            if (currentPlayerData.data.sentReport) {
                Processing // early return, since we don't care about rounds anymore after report is sent
            } else {
                val chain = peopleChain()

                val currentPlayerIndexes = videoGameRepository.getPlayerIndexes(
                    chainId = chain.id,
                    at = blockHash,
                    player = currentPlayerData.key
                ).getOrEmpty()

                val rounds = getRounds(
                    chain = chain,
                    at = blockHash,
                    currentPlayerIndexes = currentPlayerIndexes,
                    playerCount = game.state.playerCount,
                    groupSize = game.maxGroupSize
                )

                rounds.fold(
                    onSuccess = {
                        InProgress(
                            playersCount = game.state.playerCount,
                            rounds = it
                        )
                    },
                    onFailure = {
                        Broken
                    }
                )
            }
        }

        is OnChainVideoGameState.PlayerProcess -> Processing
        OnChainVideoGameState.Cancelling -> Cancelling
    }

    private suspend fun getRounds(
        chain: Chain,
        at: BlockHash?,
        currentPlayerIndexes: List<Int>,
        playerCount: Int,
        groupSize: Int
    ): Result<List<VideoGameRound>> = runCatching {
        VideoGameGroupAssignment.roundKeys(playerCount, groupSize, currentPlayerIndexes, includeSelf = true)
    }.flatMap { indexesInRounds ->
        videoGameRepository.getPlayersByIndexes(chain.id, at, indexesInRounds)
    }.flatMap { keyedPlayers ->
        val allPlayers = keyedPlayers.values

        videoGameRepository.resolvePlayerAccountIds(chain.id, allPlayers)
            .mapCatching { constructAccountIdsForRounds(keyedPlayers, it) }
    }

    private fun constructAccountIdsForRounds(
        playersByRoundKey: Map<OnChainVideoGamePlayerRoundKey, OnChainAccountOrPerson>,
        playerToAccountIdMapping: Map<OnChainAccountOrPerson, AccountId>
    ): List<VideoGameRound> {
        return playersByRoundKey
            .entries
            .groupBy { it.key.roundIndex }
            .map { (roundIndex, roundPlayers) ->
                val accountIds = roundPlayers
                    .sortedBy { it.key.playerIndex }
                    .map { (_, player) -> playerToAccountIdMapping.getValue(player) }

                VideoGameRound(accountIds, roundIndex)
            }
            .sortedBy { it.roundIndex }
    }

    private fun createNonRegisteredPlayerGameState(game: OnChainVideoGameInfo) = when (game.state) {
        is OnChainVideoGameState.Registration -> Registration
        else -> Missed
    }

    private fun Long.toMillis(): Timestamp = this * 1000
}
