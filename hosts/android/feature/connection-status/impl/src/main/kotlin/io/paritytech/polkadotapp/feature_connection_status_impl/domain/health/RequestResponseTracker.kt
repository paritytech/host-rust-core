package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import java.util.IdentityHashMap

/**
 * Estimates request round-trip latency from pending-set churn: a request first seen in the pending
 * set that later disappears is treated as completed, and its time-in-flight is recorded. Reports the
 * average completed round-trip over a sliding [windowMillis]. Requests are tracked by referential
 * identity (Sendable has no id). Not thread-safe — drive it from a single collector.
 */
class RequestResponseTracker(private val windowMillis: Long) {
    private val firstSeenMillis = IdentityHashMap<Any, Long>()
    private val completions = ArrayDeque<Completion>()

    /** Reconcile with the current [pending] set and return the average recent round-trip, or null. */
    fun update(pending: Set<Any>, nowMillis: Long): Long? {
        // Requests that left the pending set have completed — record their time-in-flight.
        firstSeenMillis.keys.filter { it !in pending }.forEach { request ->
            val start = firstSeenMillis.remove(request) ?: return@forEach
            completions.addLast(Completion(atMillis = nowMillis, durationMillis = nowMillis - start))
        }

        // Newly-seen requests start their clock now.
        pending.forEach { request ->
            if (!firstSeenMillis.containsKey(request)) firstSeenMillis[request] = nowMillis
        }

        // Forget completions older than the window.
        val cutoff = nowMillis - windowMillis
        while (completions.isNotEmpty() && completions.first().atMillis < cutoff) completions.removeFirst()

        return if (completions.isEmpty()) null else completions.sumOf { it.durationMillis } / completions.size
    }

    private data class Completion(val atMillis: Long, val durationMillis: Long)
}
