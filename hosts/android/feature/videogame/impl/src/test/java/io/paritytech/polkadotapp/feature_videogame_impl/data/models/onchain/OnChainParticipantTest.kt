package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import junit.framework.TestCase.assertEquals
import org.junit.Test

class OnChainParticipantTest {
    @Test
    fun `starting from zero`() {
        val result = calculatePendingPersonhoodScore(
            currentScore = 0,
            attendedStreak = 0,
            personhoodThreshold = 21
        )

        assertEquals(6, result.gamesLeft)
    }

    @Test
    fun `respects existing score and streak`() {
        val result = calculatePendingPersonhoodScore(
            currentScore = 1,
            attendedStreak = 1,
            personhoodThreshold = 21
        )

        assertEquals(5, result.gamesLeft)
    }

    @Test
    fun `mid-progress calculation`() {
        val result = calculatePendingPersonhoodScore(
            currentScore = 10,
            attendedStreak = 4,
            personhoodThreshold = 21
        )

        assertEquals(2, result.gamesLeft)
    }

    @Test
    fun `minimal threshold`() {
        val result = calculatePendingPersonhoodScore(
            currentScore = 0,
            attendedStreak = 0,
            personhoodThreshold = 1
        )

        assertEquals(1, result.gamesLeft)
    }
}
