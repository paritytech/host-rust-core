package io.paritytech.polkadotapp.gameState

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRound
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.VideoGameLogicStateCalculator
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.HostingState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.PreConnection
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameStages
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

class VideoGameLogicStateCalculatorTest {
    private val calculator = VideoGameLogicStateCalculator()

    private val player1: AccountId = byteArrayOf(1).toDataByteArray()
    private val player2: AccountId = byteArrayOf(2).toDataByteArray()
    private val player3: AccountId = byteArrayOf(3).toDataByteArray()
    private val player4: AccountId = byteArrayOf(4).toDataByteArray()

    private val gameDuration = (REPORT_END - GAME_START).milliseconds

    private val singleRoundDuration = VideoGameTimings.HOST_FULL_CYCLE * 2
    private val singleRoundSlot = singleRoundDuration / 2
    private val singleRoundHostingDuration = singleRoundSlot -
        VideoGameTimings.HOST_INTRODUCTION -
        VideoGameTimings.HOST_ENDING

    private val multiRoundDuration = VideoGameTimings.HOST_FULL_CYCLE * 4

    private fun gameInfo() = gameInfo(
        playersCount = 2,
        rounds = listOf(VideoGameRound(players = listOf(player1, player2), roundIndex = 0)),
    )

    private fun multiRoundGameInfo() = gameInfo(
        playersCount = 4,
        rounds = listOf(
            VideoGameRound(players = listOf(player1, player2), roundIndex = 0),
            VideoGameRound(players = listOf(player3, player4), roundIndex = 1),
        ),
    )

    private fun gameInfo(playersCount: Int, rounds: List<VideoGameRound>) = VideoGameInfo(
        index = GameIndex(1),
        registrationEnd = 0L,
        gameStartMillis = GAME_START,
        reportEnd = REPORT_END,
        rounds = rounds.size,
        preferredMaxGroupSize = 4,
        state = VideoGameState.InProgress(playersCount = playersCount, rounds = rounds),
        airdropScheduled = false,
    )

    @Test
    fun `waiting room before the game starts`() {
        val snapshot = calculator.calculate((-30).seconds, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.WaitingRoom
        assertEquals(Duration.ZERO, state.endsAt)
    }

    @Test
    fun `connection stage opens with the round-0 roster within 20s before start`() {
        val snapshot = calculator.calculate((-15).seconds, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.WaitingRoom
        assertNotNull(state.preConnection)
        assertEquals(listOf(player1, player2), state.preConnection?.players)
    }

    @Test
    fun `connection stage is closed earlier than 20s before start`() {
        val snapshot = calculator.calculate((-25).seconds, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.WaitingRoom
        assertNull(state.preConnection)
    }

    @Test
    fun `connection stage stays open at the 10s legacy boundary`() {
        val snapshot = calculator.calculate((-9).seconds, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.WaitingRoom
        assertNotNull(state.preConnection)
    }

    @Test
    fun `first host introduction right after the game starts`() {
        val snapshot = calculator.calculate(1.seconds, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(0, state.roundIndex)
        assertEquals(player1, state.currentHost)
        assertEquals(HostingState.Introduction(VideoGameTimings.HOST_INTRODUCTION), state.hostingState)
        assertEquals(VideoGameStages(currentStage = 1, stagesCount = 2), snapshot.stages)
    }

    @Test
    fun `first host active phase carries the slot-derived duration`() {
        val gameTime = VideoGameTimings.HOST_INTRODUCTION + 1.seconds

        val snapshot = calculator.calculate(gameTime, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(player1, state.currentHost)
        val hosting = state.hostingState as HostingState.Hosting
        assertEquals(singleRoundHostingDuration, hosting.duration)
        assertEquals(VideoGameTimings.HOST_INTRODUCTION + singleRoundHostingDuration, hosting.endsAt)
    }

    @Test
    fun `first host ending phase at the end of the slot`() {
        val gameTime = singleRoundSlot - 1.seconds

        val snapshot = calculator.calculate(gameTime, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(player1, state.currentHost)
        assertEquals(HostingState.Ending(singleRoundSlot), state.hostingState)
    }

    @Test
    fun `hosting hands off to the second player after the first slot`() {
        val gameTime = singleRoundSlot + 1.seconds

        val snapshot = calculator.calculate(gameTime, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(player2, state.currentHost)
        assertTrue(state.hostingState is HostingState.Introduction)
        assertEquals(VideoGameStages(currentStage = 2, stagesCount = 2), snapshot.stages)
    }

    @Test
    fun `reporting after all rounds complete`() {
        val gameTime = singleRoundDuration + 1.seconds

        val snapshot = calculator.calculate(gameTime, gameInfo())

        val state = snapshot.processState as VideoGameProcessState.Reporting
        assertEquals(gameDuration, state.endsAt)
        assertEquals(VideoGameStages(currentStage = 2, stagesCount = 2), snapshot.stages)
    }

    @Test
    fun `finished after the reporting window ends`() {
        val snapshot = calculator.calculate(gameDuration + 1.seconds, gameInfo())

        assertEquals(VideoGameProcessState.Finished, snapshot.processState)
    }

    @Test
    fun `error when the game is not in progress after start`() {
        val info = VideoGameInfo(
            index = GameIndex(1),
            registrationEnd = 0L,
            gameStartMillis = GAME_START,
            reportEnd = REPORT_END,
            rounds = 1,
            preferredMaxGroupSize = 4,
            state = VideoGameState.Registration,
            airdropScheduled = false,
        )

        val snapshot = calculator.calculate(5.seconds, info)

        assertTrue(snapshot.processState is VideoGameProcessState.Error)
    }

    @Test
    fun `round pre-connection opens with the next round roster near the round end`() {
        val gameTime = multiRoundDuration - 7.seconds

        val snapshot = calculator.calculate(gameTime, multiRoundGameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(0, state.roundIndex)
        assertEquals(PreConnection(listOf(player3, player4)), state.preConnection)
    }

    @Test
    fun `round pre-connection stays closed earlier than the pre-connect window`() {
        val gameTime = multiRoundDuration - VideoGameTimings.PRE_CONNECTION_TIME - 5.seconds

        val snapshot = calculator.calculate(gameTime, multiRoundGameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(0, state.roundIndex)
        assertNull(state.preConnection)
    }

    @Test
    fun `second round starts with its own roster and continues the stage count`() {
        val gameTime = multiRoundDuration + 1.seconds

        val snapshot = calculator.calculate(gameTime, multiRoundGameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(1, state.roundIndex)
        assertEquals(player3, state.currentHost)
        assertEquals(listOf(player3, player4), state.roundPlayers)
        assertTrue(state.hostingState is HostingState.Introduction)
        assertEquals(VideoGameStages(currentStage = 3, stagesCount = 4), snapshot.stages)
    }

    @Test
    fun `final round has no pre-connection`() {
        val gameTime = multiRoundDuration * 2 - 5.seconds

        val snapshot = calculator.calculate(gameTime, multiRoundGameInfo())

        val state = snapshot.processState as VideoGameProcessState.Round
        assertEquals(1, state.roundIndex)
        assertNull(state.preConnection)
    }
}

private const val GAME_START = 100_000L
private const val REPORT_END = 200_000L
