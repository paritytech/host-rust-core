import os

/// Coalesces concurrent async calls into a single in-flight task.
///
/// When multiple callers invoke ``run(_:)`` concurrently, only the first
/// starts the work. Subsequent callers await the same `Task` and receive
/// the same result. Once the task completes, the next call starts fresh.
///
/// ```swift
/// let fetch = CoalescingTask<String>()
/// let token = try await fetch.run { try await obtainToken() }
/// ```
public final class CoalescingTask<Value: Sendable>: Sendable {
    private let inflight = OSAllocatedUnfairLock<Task<Value, Error>?>(initialState: nil)

    public init() {}

    public func run(_ operation: @Sendable @escaping () async throws -> Value) async throws -> Value {
        let task: Task<Value, Error> = inflight.withLock { current in
            if let existing = current {
                return existing
            }
            let newTask = Task<Value, Error> {
                defer { self.inflight.withLock { $0 = nil } }
                return try await operation()
            }
            current = newTask
            return newTask
        }
        return try await task.value
    }
}
