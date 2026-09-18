package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import kotlin.time.Duration
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

@OptIn(ExperimentalTime::class)
class BlockArrivalWindow(private val window: Duration) {
    private val arrivals = ArrayDeque<Instant>()

    // Kept outside the deque: a stall long enough to empty the window is exactly when the caller
    // still needs to know when the last block landed.
    private var lastArrival: Instant? = null

    fun recordArrival(at: Instant) {
        arrivals.addLast(at)
        lastArrival = at
    }

    fun clear() {
        arrivals.clear()
        lastArrival = null
    }

    fun lastArrival(): Instant? = lastArrival

    fun pruneAndCount(now: Instant): Int {
        val cutoff = now - window
        while (arrivals.isNotEmpty() && arrivals.first() < cutoff) arrivals.removeFirst()
        return arrivals.size
    }
}
