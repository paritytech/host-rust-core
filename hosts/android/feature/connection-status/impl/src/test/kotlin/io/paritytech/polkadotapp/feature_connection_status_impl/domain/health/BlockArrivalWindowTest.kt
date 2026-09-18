package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import kotlin.time.Duration.Companion.seconds
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

@OptIn(ExperimentalTime::class)
class BlockArrivalWindowTest {
    @Test
    fun `counts arrivals inside the window`() {
        val window = BlockArrivalWindow(window = 30.seconds)
        listOf(0, 6, 12, 18, 24).forEach { window.recordArrival(at(it)) }

        assertEquals(5, window.pruneAndCount(at(29)))
    }

    @Test
    fun `drops arrivals once they fall out of the window`() {
        val window = BlockArrivalWindow(window = 30.seconds)
        listOf(0, 6, 12).forEach { window.recordArrival(at(it)) }

        assertEquals(2, window.pruneAndCount(at(31)))
        assertEquals(0, window.pruneAndCount(at(50)))
    }

    @Test
    fun `an arrival exactly one window old still counts`() {
        val window = BlockArrivalWindow(window = 30.seconds)
        window.recordArrival(at(1))

        assertEquals(1, window.pruneAndCount(at(31)))
        assertEquals(0, window.pruneAndCount(Instant.fromEpochMilliseconds(31_001)))
    }

    @Test
    fun `remembers the last arrival after the window has emptied`() {
        val window = BlockArrivalWindow(window = 30.seconds)
        window.recordArrival(at(5))

        assertEquals(0, window.pruneAndCount(at(90)))
        assertEquals(at(5), window.lastArrival())
    }

    @Test
    fun `a reconnect forgets the last arrival`() {
        val window = BlockArrivalWindow(window = 30.seconds)
        window.recordArrival(at(5))
        window.clear()

        assertNull(window.lastArrival())
    }

    private fun at(seconds: Int): Instant = Instant.fromEpochMilliseconds(seconds * 1_000L)
}
