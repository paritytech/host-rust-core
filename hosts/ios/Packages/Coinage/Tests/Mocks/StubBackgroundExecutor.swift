import Foundation
import BackgroundExecution

/// Runs the operation inline, with no OS background assertion — deterministic for tests.
struct StubBackgroundExecutor: BackgroundExecuting {
    func execute<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}
