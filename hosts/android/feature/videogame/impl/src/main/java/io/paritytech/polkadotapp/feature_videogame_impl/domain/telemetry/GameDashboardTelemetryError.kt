package io.paritytech.polkadotapp.feature_videogame_impl.domain.telemetry

/**
 * Classification of a dashboard-transport failure.
 *
 * Transport produces these; the emitter reads them to decide retry policy.
 * [Transient] = HTTP 429 / 5xx / IO failures (retry-worthy);
 * [NonRetryable] = other 4xx (terminal — backend rejected the payload).
 */
sealed class GameDashboardTelemetryError(cause: Throwable? = null) : Exception(cause) {
    class Transient(cause: Throwable) : GameDashboardTelemetryError(cause)
    class NonRetryable(val statusCode: Int, cause: Throwable) : GameDashboardTelemetryError(cause)
}
