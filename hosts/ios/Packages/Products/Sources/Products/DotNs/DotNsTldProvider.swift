import Foundation
import os
import StructuredConcurrency

public protocol DotNsTldStoring: Sendable {
    func loadTld() -> String?
    func saveTld(_ tld: String)
}

/// Single chain read of the network's TLD label, without the leading dot.
public protocol DotNsTldReading: Sendable {
    func readTld() async throws -> String
}

public protocol DotNsTldProviding: Sendable {
    /// Cached TLD label without the leading dot, or nil until a chain read has succeeded.
    /// Kicks a background refresh when nil and the backoff window has elapsed.
    func currentTld() -> String?

    /// Resolves the TLD, sharing any in-flight read. Bypasses the backoff window,
    /// subject to a minimum inter-attempt floor.
    func resolveTld() async throws -> String

    /// Kicks a background re-read of the TLD, subject to the backoff window. Non-blocking.
    func refresh()
}

public final class DotNsTldProvider: DotNsTldProviding {
    private let reader: DotNsTldReading
    private let now: @Sendable () -> Date
    private let store: DotNsTldStoring?
    private let persistedTld: String?
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let coalescer = CoalescingTask<String>()

    private static let minimumInterAttemptInterval: TimeInterval = 1
    private static let maximumBackoff: TimeInterval = 60

    private struct State {
        var tld: String?
        var failureCount: Int = 0
        var nextAttemptAt: Date = .distantPast
        var nextStartAllowedAt: Date = .distantPast
    }

    public init(
        reader: DotNsTldReading,
        store: DotNsTldStoring? = nil,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.reader = reader
        self.store = store
        persistedTld = store?.loadTld()
        self.now = now
    }

    public func currentTld() -> String? {
        if let tld = state.withLock({ $0.tld }) { return tld }
        refreshIfNeeded()
        return persistedTld
    }

    public func resolveTld() async throws -> String {
        if let tld = state.withLock({ $0.tld }) { return tld }

        return try await coalescer.run { [self] in
            // A joiner arriving after a successful read must not trigger a second one.
            if let tld = state.withLock({ $0.tld }) { return tld }
            guard claimStart(ignoringBackoff: true) else { throw DotNsContractError.tldNotFound }
            return try await performRead()
        }
    }

    public func refresh() {
        refreshIfNeeded()
    }
}

private extension DotNsTldProvider {
    /// Reserves the right to start a chain read, applying the minimum inter-attempt
    /// floor and (unless bypassed) the failure backoff window.
    /// - Returns: `true` when the caller may proceed with a read.
    func claimStart(ignoringBackoff: Bool) -> Bool {
        state.withLock { state in
            let currentTime = now()
            guard currentTime >= state.nextStartAllowedAt else { return false }
            guard ignoringBackoff || currentTime >= state.nextAttemptAt else { return false }
            state.nextStartAllowedAt = currentTime.addingTimeInterval(Self.minimumInterAttemptInterval)
            return true
        }
    }

    func performRead() async throws -> String {
        do {
            let tld = try await reader.readTld()
            finish(.success(tld))
            store?.saveTld(tld)
            return tld
        } catch {
            finish(.failure(error))
            throw error
        }
    }

    func refreshIfNeeded() {
        guard claimStart(ignoringBackoff: false) else { return }
        Task(priority: .utility) { [weak self] in
            guard let provider = self else { return }
            _ = try? await provider.coalescer.run {
                if let tld = provider.state.withLock({ $0.tld }) { return tld }
                return try await provider.performRead()
            }
        }
    }

    func finish(_ result: Result<String, Error>) {
        state.withLock { state in
            switch result {
            case let .success(tld):
                state.tld = tld
                state.failureCount = 0
                state.nextAttemptAt = .distantPast
            case .failure:
                state.failureCount += 1
                let backoff = min(pow(2.0, Double(state.failureCount)), Self.maximumBackoff)
                state.nextAttemptAt = now().addingTimeInterval(backoff)
            }
        }
    }
}
