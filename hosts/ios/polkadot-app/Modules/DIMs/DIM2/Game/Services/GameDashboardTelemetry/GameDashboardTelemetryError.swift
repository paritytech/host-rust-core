import Foundation

/// Typed transport-level failure for the dashboard.
///
/// Transport classifies the failure; the emitter decides what to do.
/// Transient errors are worth retrying; non-retryable ones are terminal.
enum GameDashboardTelemetryError: Error {
    case transient(underlying: Error)
    case nonRetryable(statusCode: Int, underlying: Error?)
    case encodingFailed(underlying: Error)
    case invalidURL
}
