package io.paritytech.polkadotapp.feature_videogame_impl.domain

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRound
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.gameDuration
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.HostingState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.PreConnection
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameSnapshot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameStages
import javax.inject.Inject
import kotlin.time.Duration

class VideoGameLogicStateCalculator @Inject constructor() {
    fun calculate(gameTime: Duration, gameInfo: VideoGameInfo): VideoGameSnapshot {
        val gameStartsAt = Duration.ZERO
        if (gameTime < gameStartsAt) {
            val firstRound = (gameInfo.state as? VideoGameState.InProgress)?.rounds?.firstOrNull()
            return gameInfo.snapshotOf(
                processState = VideoGameProcessState.WaitingRoom(
                    endsAt = gameStartsAt,
                    preConnection = createPreConnection(
                        nextRound = firstRound,
                        gameTime = gameTime,
                        currentStateEndsAt = gameStartsAt,
                        preConnectWindow = VideoGameTimings.CONNECTION_STAGE_DURATION
                    )
                ),
                stages = VideoGameStages.Empty
            )
        }

        if (gameTime >= getReportingEndsAt(gameInfo)) {
            return gameInfo.snapshotOf(
                processState = VideoGameProcessState.Finished,
                stages = VideoGameStages.Empty
            )
        }

        val inProgressState = gameInfo.state as? VideoGameState.InProgress
            ?: return gameInfo.snapshotOf(
                processState = VideoGameProcessState.Error(
                    IllegalStateException("Game is not in InProgress state to calculate active process state. Current state: ${gameInfo.state::class.simpleName}")
                ),
                stages = VideoGameStages.Empty
            )

        return handleInProgressState(gameTime, gameInfo, inProgressState)
    }

    private fun handleInProgressState(
        gameTime: Duration,
        gameInfo: VideoGameInfo,
        inProgressState: VideoGameState.InProgress
    ): VideoGameSnapshot {
        val roundDuration = getRoundDuration(
            preferredMaxGroupSize = gameInfo.preferredMaxGroupSize,
            playersCount = inProgressState.playersCount
        )

        val reportingStartsAt = getReportingStartsAt(
            roundDuration = roundDuration,
            roundsCount = gameInfo.rounds
        )

        val stagesCount = inProgressState.rounds.sumOf { it.players.size }

        if (gameTime >= reportingStartsAt) {
            return gameInfo.snapshotOf(
                processState = VideoGameProcessState.Reporting(getReportingEndsAt(gameInfo)),
                stages = VideoGameStages(currentStage = stagesCount, stagesCount = stagesCount)
            )
        }

        val rounds = inProgressState.rounds

        var cursor = Duration.ZERO
        var stageIndex = 0

        rounds.forEachIndexed { index, round ->
            val roundEndsAt = cursor + roundDuration
            val roundState = createRoundState(
                roundIndex = index,
                roundPlayers = round.players,
                gameTime = gameTime,
                roundStartTime = cursor,
                roundDuration = roundDuration,
                stageIndexStart = stageIndex,
                preConnection = createPreConnection(
                    nextRound = rounds.getOrNull(index + 1),
                    gameTime = gameTime,
                    currentStateEndsAt = roundEndsAt,
                    preConnectWindow = VideoGameTimings.PRE_CONNECTION_TIME
                )
            )
            if (roundState != null) {
                val (processState, currentStage) = roundState

                return gameInfo.snapshotOf(
                    processState = processState,
                    stages = VideoGameStages(currentStage = currentStage, stagesCount = stagesCount)
                )
            }

            stageIndex += round.players.size
            cursor = roundEndsAt
        }

        return gameInfo.snapshotOf(
            processState = VideoGameProcessState.Reporting(getReportingEndsAt(gameInfo)),
            stages = VideoGameStages(currentStage = stagesCount, stagesCount = stagesCount)
        )
    }

    private fun createPreConnection(
        nextRound: VideoGameRound?,
        gameTime: Duration,
        currentStateEndsAt: Duration,
        preConnectWindow: Duration
    ): PreConnection? {
        val nextRoundIn = currentStateEndsAt - gameTime
        if (nextRoundIn.isNegative()) return null

        val shouldPreConnect = nextRoundIn < preConnectWindow

        return if (nextRound != null && shouldPreConnect) {
            PreConnection(nextRound.players)
        } else null
    }

    private fun createRoundState(
        roundIndex: Int,
        roundPlayers: List<AccountId>,
        gameTime: Duration,
        roundStartTime: Duration,
        roundDuration: Duration,
        stageIndexStart: Int,
        preConnection: PreConnection?
    ): Pair<VideoGameProcessState.Round, Int>? {
        var cursor = roundStartTime
        val hostingSlotDurationPerPlayer = roundDuration / roundPlayers.size

        val actualHostingDuration = hostingSlotDurationPerPlayer -
            VideoGameTimings.HOST_INTRODUCTION -
            VideoGameTimings.HOST_ENDING

        roundPlayers.forEachIndexed { playerIndex, currentHost ->
            val currentStage = stageIndexStart + playerIndex + 1

            var hostPhaseEndsAt = cursor + VideoGameTimings.HOST_INTRODUCTION
            if (gameTime < hostPhaseEndsAt) {
                return VideoGameProcessState.Round(
                    roundIndex = roundIndex,
                    roundPlayers = roundPlayers,
                    currentHost = currentHost,
                    hostingState = HostingState.Introduction(hostPhaseEndsAt),
                    preConnection = preConnection
                ) to currentStage
            }
            cursor = hostPhaseEndsAt

            hostPhaseEndsAt = cursor + actualHostingDuration
            if (gameTime < hostPhaseEndsAt) {
                return VideoGameProcessState.Round(
                    roundIndex = roundIndex,
                    roundPlayers = roundPlayers,
                    currentHost = currentHost,
                    hostingState = HostingState.Hosting(hostPhaseEndsAt, actualHostingDuration),
                    preConnection = preConnection
                ) to currentStage
            }
            cursor = hostPhaseEndsAt

            hostPhaseEndsAt = cursor + VideoGameTimings.HOST_ENDING
            if (gameTime < hostPhaseEndsAt) {
                return VideoGameProcessState.Round(
                    roundIndex = roundIndex,
                    roundPlayers = roundPlayers,
                    currentHost = currentHost,
                    hostingState = HostingState.Ending(hostPhaseEndsAt),
                    preConnection = preConnection
                ) to currentStage
            }
            cursor = hostPhaseEndsAt
        }

        return null
    }

    private fun getLargestGroupSize(
        preferredMaxGroupSize: Int,
        numberOfPlayers: Int
    ): Int {
        val numberOfGroups = if (numberOfPlayers % preferredMaxGroupSize == 0) {
            numberOfPlayers / preferredMaxGroupSize
        } else {
            (numberOfPlayers / preferredMaxGroupSize) + 1
        }

        val baseSize = numberOfPlayers / numberOfGroups
        val remainder = numberOfPlayers % numberOfGroups

        return if (remainder > 0) {
            baseSize + 1
        } else {
            baseSize
        }
    }

    private fun getReportingStartsAt(roundDuration: Duration, roundsCount: Int) =
        roundDuration * roundsCount

    private fun getReportingEndsAt(gameInfo: VideoGameInfo): Duration = gameInfo.gameDuration()

    private fun getRoundDuration(preferredMaxGroupSize: Int, playersCount: Int): Duration {
        val largestGroupSize = getLargestGroupSize(preferredMaxGroupSize, playersCount)

        return VideoGameTimings.HOST_FULL_CYCLE * largestGroupSize
    }

    private fun VideoGameInfo.snapshotOf(
        processState: VideoGameProcessState,
        stages: VideoGameStages
    ) = VideoGameSnapshot(
        gameIndex = index,
        processState = processState,
        stages = stages
    )
}
