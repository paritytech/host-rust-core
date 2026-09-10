package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonhoodStatus
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.isExternallyRecognized
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.getCurrentActiveGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.FullVideoGameReport
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameReport
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRound
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.BannedPlayersRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.PlayerFrameFilePathCreator
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameReportSnapshot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameVote
import io.paritytech.polkadotapp.feature_videogame_impl.domain.telemetry.GameDashboardTelemetryEmitter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGameExtrinsicTags
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGamePlayerKeyResolver
import io.paritytech.polkadotapp.feature_videogame_impl.domain.tracked.VideoGameTrackedSubmission
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.PlayingAccountUseCase
import kotlinx.coroutines.flow.first
import timber.log.Timber
import javax.inject.Inject

interface VideoGameVoteInteractor {
    context(scope: ComputationalScope)
    suspend fun getFrameUri(accountId: AccountId): String

    context(scope: ComputationalScope)
    suspend fun getVotesForCurrentGame(): List<VideoGameVote>

    context(scope: ComputationalScope)
    suspend fun submitVotes(finalVotes: Map<AccountId, Boolean>): Result<Unit>

    suspend fun getBannedAccountIds(): Set<AccountId>
}

class RealVideoGameVoteInteractor @Inject constructor(
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val gameInfoSyncService: VideoGameInfoSyncService,
    private val chainRegistry: ChainRegistry,
    private val playingAccountUseCase: PlayingAccountUseCase,
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val frameFilePathCreator: PlayerFrameFilePathCreator,
    private val bannedPlayersRepository: BannedPlayersRepository,
    private val personStatusUseCase: PersonStatusUseCase,
    private val reportSnapshot: GameReportSnapshot,
    private val gameDashboardTelemetry: GameDashboardTelemetryEmitter,
    private val playerKeyResolver: VideoGamePlayerKeyResolver,
) : VideoGameVoteInteractor {
    context(scope: ComputationalScope)
    override suspend fun getFrameUri(accountId: AccountId): String {
        val gameIndex = gameInfoSyncService.getCurrentActiveGameInfo().index
        return frameFilePathCreator.getEncodedUri(gameIndex.value, accountId)
    }

    context(scope: ComputationalScope)
    override suspend fun getVotesForCurrentGame(): List<VideoGameVote> {
        val gameIndex = gameInfoSyncService.getCurrentActiveGameInfo().index
        return videoGameRepository.getSavedVotesForGame(gameIndex)
    }

    context(scope: ComputationalScope)
    override suspend fun submitVotes(finalVotes: Map<AccountId, Boolean>) = runCatching {
        // Snapshot report-time state the results screen needs but which is gone by then:
        // membership (just-became-member vs existing) and playerCount (only exposed while the
        // game is in Reporting; Fast Attendance moves it to PlayerProcess before results open).
        // Guarded: never fails the submit.
        captureReportSnapshot()

        val rounds = getCurrentGameRounds()
        val currentPlayerAccountId = playingAccountUseCase.getOurPlayerAccountId()
        val opponentVerdicts = collectOpponentVerdicts(rounds, finalVotes, currentPlayerAccountId)
        val verdictEntries = opponentVerdicts.toVerdictEntries()

        Triple(currentPlayerAccountId, verdictEntries, opponentVerdicts.toFullReport())
    }.flatMap { (currentPlayerAccountId, verdictEntries, fullReport) ->
        submitReport(chainRegistry.peopleChain(), fullReport)
            .onSuccess {
                videoGameRepository.clearVotes()
                gameDashboardTelemetry.submitEnd(localAccount = currentPlayerAccountId, rounds = verdictEntries)
            }
    }

    private fun List<List<Pair<AccountId, Boolean>>>.toVerdictEntries(): List<List<GameDashboardTelemetryRepository.VerdictEntry>> =
        map { round ->
            round.map { (player, isPerson) ->
                GameDashboardTelemetryRepository.VerdictEntry(
                    accountId = player,
                    verdict = if (isPerson) GameDashboardTelemetryRepository.Verdict.Person else GameDashboardTelemetryRepository.Verdict.NotPerson
                )
            }
        }

    private fun collectOpponentVerdicts(
        rounds: List<VideoGameRound>,
        finalVotes: Map<AccountId, Boolean>,
        currentPlayerAccountId: AccountId
    ): List<List<Pair<AccountId, Boolean>>> =
        rounds.map { round ->
            round.players.mapNotNull { playerAccountId ->
                if (playerAccountId != currentPlayerAccountId) {
                    playerAccountId to finalVotes.getOrDefault(playerAccountId, false)
                } else {
                    null
                }
            }
        }

    private fun List<List<Pair<AccountId, Boolean>>>.toFullReport(): FullVideoGameReport =
        map { round ->
            round.map { (_, isPerson) ->
                if (isPerson) VideoGameReport.Person else VideoGameReport.NotPerson
            }
        }

    context(scope: ComputationalScope)
    private suspend fun captureReportSnapshot() {
        val wasRegistered = runCatching {
            personStatusUseCase.personhoodStatusFlow().first() != PersonhoodStatus.NotPerson
        }
            .onFailure { Timber.w(it, "Personhood status read failed; assuming already registered") }
            .getOrDefault(true)
        val playerCount = runCatching {
            (gameInfoSyncService.getCurrentActiveGameInfo().state as? VideoGameState.InProgress)?.playersCount
        }.getOrNull()
        reportSnapshot.capture(wasRegistered = wasRegistered, playerCount = playerCount)
    }

    context(scope: ComputationalScope)
    private suspend fun submitReport(
        chain: Chain,
        report: FullVideoGameReport
    ): Result<Unit> {
        val externallyRecognized = gamesProgressUseCase.videoGameProgress().isExternallyRecognized()
        val gameIndex = gameInfoSyncService.getCurrentActiveGameInfo().index
        val submission = VideoGameTrackedSubmission(
            tag = VideoGameExtrinsicTags.vote(gameIndex),
            player = playerKeyResolver.resolve(externallyRecognized),
            gameIndex = gameIndex,
        )

        return if (externallyRecognized) {
            videoGameRepository.submitReportAsPerson(chain, report, submission)
        } else {
            videoGameRepository.submitReportAsAccount(chain, report, submission)
        }
    }

    context(scope: ComputationalScope)
    private suspend fun getCurrentGameRounds(): List<VideoGameRound> {
        val gameInfo = gameInfoSyncService.getCurrentActiveGameInfo()

        return (gameInfo.state as VideoGameState.InProgress).rounds
    }

    override suspend fun getBannedAccountIds() = bannedPlayersRepository.subscribeBannedPlayers().first().toSet()
}
