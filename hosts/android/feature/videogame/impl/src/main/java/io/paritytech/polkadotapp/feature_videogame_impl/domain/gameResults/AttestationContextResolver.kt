package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeOurPlayer
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.PlayingAccountUseCase
import kotlinx.coroutines.flow.first
import javax.inject.Inject

/**
 * The on-chain context every results phase needs: who is being attested, in which game, the
 * deterministic candidate set, and the chain-authoritative `passed` verdict. Resolved once for
 * the initial payload and again per mint during the live phase.
 */
internal data class AttestationContext(
    val chainId: ChainId,
    val gameIndex: GameIndex,
    val attestee: OnChainAccountOrPerson,
    val candidates: GameAttestationCandidates,
    val earlyAttendance: Boolean?,
)

class AttestationContextResolver @Inject constructor(
    private val playingAccountUseCase: PlayingAccountUseCase,
    private val chainRegistry: ChainRegistry,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val gameGroupRosterService: GameGroupRosterService,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val reportSnapshot: GameReportSnapshot,
    private val scoreContextProvider: ScoreContextProvider,
) {
    context(scope: ComputationalScope)
    internal suspend fun resolve(): AttestationContext? {
        val chain = chainRegistry.peopleChain()
        val playingAccount = playingAccountUseCase.getPlayingAccount()
        val ourAccountId = playingAccountUseCase.getOurPlayerAccountId()
        val ourScoreAlias = bandersnatchSecretsStorage.getAliasInContext(playingAccount.id, scoreContextProvider.context())

        val playerData = videoGameRepository.subscribeOurPlayer(chain.id, ourAccountId, ourScoreAlias).first()
        val gameInfo = videoGameRepository.subscribeGameInfo(chain.id).first()
        val attestee = playerData?.key
        // playerCount is on-chain only while Reporting; Fast Attendance drops it at PlayerProcess,
        // so fall back to the count snapshotted at report-submit time.
        val playerCount = (gameInfo?.state as? OnChainVideoGameState.Reporting)?.playerCount
            ?: reportSnapshot.current()?.playerCount

        if (gameInfo == null || attestee == null || playerCount == null) return null

        // The local Players cache can lag the chain — mints land when attendance finalises
        val freshPlayer = videoGameRepository.getPlayer(chain.id, attestee)
            .logFailure("[GameResults] fresh player read failed; using cached row")
            .getOrNull()
        val earlyAttendance = (freshPlayer ?: playerData.data)?.earlyAttendanceEnactment?.attendance

        val candidates = gameGroupRosterService.computeCandidates(
            chainId = chain.id,
            at = null,
            gameIndex = gameInfo.index,
            attestee = attestee,
            maxGroupSize = gameInfo.maxGroupSize,
            playerCount = playerCount,
        ).getOrNull() ?: return null

        return AttestationContext(
            chainId = chain.id,
            gameIndex = gameInfo.index,
            attestee = attestee,
            candidates = candidates,
            earlyAttendance = earlyAttendance,
        )
    }
}
