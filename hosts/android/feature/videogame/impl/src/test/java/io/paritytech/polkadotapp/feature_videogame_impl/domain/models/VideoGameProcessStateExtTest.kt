package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.intoAccountId
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.time.Duration

class VideoGameProcessStateExtTest {
    private val player: AccountId = byteArrayOf(0x01).intoAccountId()

    @Test
    fun `camera off in waiting room before the pre-connection window`() {
        val state = VideoGameProcessState.WaitingRoom(endsAt = Duration.ZERO, preConnection = null)

        assertFalse(state.requiresLocalCamera())
    }

    @Test
    fun `camera on in waiting room during the pre-connection window`() {
        val state = VideoGameProcessState.WaitingRoom(
            endsAt = Duration.ZERO,
            preConnection = PreConnection(players = listOf(player)),
        )

        assertTrue(state.requiresLocalCamera())
    }

    @Test
    fun `camera on during a round`() {
        val state = VideoGameProcessState.Round(
            roundIndex = 0,
            roundPlayers = listOf(player),
            currentHost = player,
            hostingState = HostingState.Introduction(endsAt = Duration.ZERO),
            preConnection = null,
        )

        assertTrue(state.requiresLocalCamera())
    }

    @Test
    fun `camera off while reporting`() {
        val state = VideoGameProcessState.Reporting(endsAt = Duration.ZERO)

        assertFalse(state.requiresLocalCamera())
    }

    @Test
    fun `camera off when finished`() {
        assertFalse(VideoGameProcessState.Finished.requiresLocalCamera())
    }

    @Test
    fun `camera off on error`() {
        assertFalse(VideoGameProcessState.Error(throwable = null).requiresLocalCamera())
    }
}
