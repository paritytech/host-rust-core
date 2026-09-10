package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes

class WaitingRoomJoinableTest {
    private val waitingRoom = VideoGameProcessState.WaitingRoom(endsAt = Duration.ZERO, preConnection = null)
    private val notRegistered = VideoGameRegistrationStage.CanRegister.NoCredibilityProofRequired(externallyRecognized = false)

    @Test
    fun `joinable when registered, in waiting room, inside the window`() {
        assertTrue(
            isWaitingRoomJoinable(
                registrationStage = VideoGameRegistrationStage.Registered,
                processState = waitingRoom,
                gameTime = (-1).minutes,
            )
        )
    }

    @Test
    fun `joinable exactly at the window boundary`() {
        assertTrue(
            isWaitingRoomJoinable(
                registrationStage = VideoGameRegistrationStage.Registered,
                processState = waitingRoom,
                gameTime = -VideoGameTimings.WAITING_ROOM_AVAILABLE_BEFORE,
            )
        )
    }

    @Test
    fun `not joinable when not registered`() {
        assertFalse(
            isWaitingRoomJoinable(
                registrationStage = notRegistered,
                processState = waitingRoom,
                gameTime = (-1).minutes,
            )
        )
    }

    @Test
    fun `not joinable more than five minutes before start`() {
        assertFalse(
            isWaitingRoomJoinable(
                registrationStage = VideoGameRegistrationStage.Registered,
                processState = waitingRoom,
                gameTime = (-6).minutes,
            )
        )
    }

    @Test
    fun `not joinable when game time is unknown`() {
        assertFalse(
            isWaitingRoomJoinable(
                registrationStage = VideoGameRegistrationStage.Registered,
                processState = waitingRoom,
                gameTime = null,
            )
        )
    }

    @Test
    fun `not joinable outside the waiting room phase`() {
        assertFalse(
            isWaitingRoomJoinable(
                registrationStage = VideoGameRegistrationStage.Registered,
                processState = VideoGameProcessState.Finished,
                gameTime = (-1).minutes,
            )
        )
    }
}
