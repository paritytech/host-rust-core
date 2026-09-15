package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

/**
 * Rolling window over the last [maxSamples] best-block inter-arrival intervals, used to compute a
 * moving-average block latency that smooths single-block jitter. Not thread-safe — drive it from a
 * single collector.
 */
class BlockLatencyWindow(private val maxSamples: Int) {
    private val intervals = ArrayDeque<Long>()
    private var lastArrival: Long? = null

    fun recordArrival(nowMillis: Long) {
        val previous = lastArrival
        lastArrival = nowMillis
        if (previous != null) {
            intervals.addLast(nowMillis - previous)
            while (intervals.size > maxSamples) intervals.removeFirst()
        }
    }

    /** Moving-average interval in millis, or null until at least one interval has been observed. */
    fun averageIntervalMillis(): Long? =
        if (intervals.isEmpty()) null else intervals.sum() / intervals.size

    fun lastArrivalMillis(): Long? = lastArrival
}
