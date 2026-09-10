package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RequestResponseTrackerTest {
    private val window = 30_000L

    @Test
    fun `no completed requests returns null`() {
        val tracker = RequestResponseTracker(window)
        val request = Any()

        assertNull(tracker.update(setOf(request), nowMillis = 0))
        assertNull(tracker.update(setOf(request), nowMillis = 1_000))
    }

    @Test
    fun `records the round-trip when a request completes`() {
        val tracker = RequestResponseTracker(window)
        val request = Any()

        tracker.update(setOf(request), nowMillis = 0)
        assertEquals(500L, tracker.update(emptySet(), nowMillis = 500))
    }

    @Test
    fun `averages completed round-trips`() {
        val tracker = RequestResponseTracker(window)
        val first = Any()
        val second = Any()

        tracker.update(setOf(first, second), nowMillis = 0)
        tracker.update(setOf(second), nowMillis = 200) // first completes in 200ms
        assertEquals(300L, tracker.update(emptySet(), nowMillis = 400)) // second in 400ms -> avg 300
    }

    @Test
    fun `forgets completions older than the window`() {
        val tracker = RequestResponseTracker(window)
        val old = Any()
        val recent = Any()

        tracker.update(setOf(old), nowMillis = 0)
        tracker.update(emptySet(), nowMillis = 100) // old completes at t=100 (dur 100)

        tracker.update(setOf(recent), nowMillis = 40_000)
        // old's completion (t=100) is now outside the 30s window -> only 'recent' counts.
        assertEquals(1_000L, tracker.update(emptySet(), nowMillis = 41_000))
    }
}
