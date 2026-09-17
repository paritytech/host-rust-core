import AsyncExtensions
import DurableTransactions
import Foundation
import os

/// The scope the in-memory ledger opens for the registration hook. A domain's in-memory store recognises
/// it and writes its own rows inside; nothing needs a transaction here, so it carries no state.
public final class InMemoryRegistrationScope: DurableTxRegistrationScope {
    public init() {}
}

/// An in-memory ``DurableTxRepositoryProtocol`` with the store's guarantees: atomic batch registration
/// (a throwing hook rolls the whole batch back), monotonic sequences, the compare-and-set status write,
/// and status / group streams.
///
/// Lock-based rather than an actor so a domain's in-memory store can read statuses synchronously from
/// inside the registration hook, the way a CoreData store reads its own context.
public final class InMemoryDurableTxRepository: DurableTxRepositoryProtocol, @unchecked Sendable {
    struct State {
        var entries: [DurableTxId: DurableTxEntry] = [:]
        var nextSequence: Int64 = 1
        var statusObservers: [DurableTxId: [AsyncStream<DurableTxStatus>.Continuation]] = [:]
        var groupObservers: [GroupKey: [AsyncStream<[DurableTxEntry]>.Continuation]] = [:]
    }

    struct GroupKey: Hashable {
        let domain: TxDomainId
        let groupId: DurableTxGroupId
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    /// Every entry, ordered by sequence — a synchronous read for domain stores and assertions.
    public var allEntries: [DurableTxEntry] {
        state.withLock { Self.sorted($0.entries) }
    }

    /// The entry's current status, read synchronously — for a domain store validating inside the hook.
    public func statusSnapshot(of id: DurableTxId) -> DurableTxStatus? {
        state.withLock { $0.entries[id]?.status }
    }

    /// Test convenience: records a prepared entry keeping its id and status, assigning the next sequence.
    public func insert(_ entry: DurableTxEntry) {
        state.withLock { current in
            current.entries[entry.id] = entry.withSequence(current.nextSequence)
            current.nextSequence += 1
            Self.notifyGroupObservers(&current)
        }
    }

    /// Test convenience (the production protocol has only the compare-and-set `updateTxStatus`): forces a
    /// status and notifies observers, for setting up scenarios.
    public func forceStatus(_ id: DurableTxId, to status: DurableTxStatus) throws {
        try state.withLock { current in
            try Self.mutate(&current, id) { $0.withStatus(status) }
            for observer in current.statusObservers[id] ?? [] {
                observer.yield(status)
            }
        }
    }

    public func register(
        _ registrations: [DurableTxRegistration],
        onRegister: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        let (snapshot, ids) = state.withLock { current -> (State, [DurableTxId]) in
            let snapshot = current
            var ids: [DurableTxId] = []
            for registration in registrations {
                let id = DurableTxId()
                current.entries[id] = registration.makeEntry(id: id, sequence: current.nextSequence)
                current.nextSequence += 1
                ids.append(id)
            }
            return (snapshot, ids)
        }

        // The hook runs outside the lock so a domain store can read this ledger while writing its rows;
        // a throw restores the snapshot, which is the rollback.
        do {
            try onRegister(InMemoryRegistrationScope(), ids)
        } catch {
            state.withLock { current in
                current.entries = snapshot.entries
                current.nextSequence = snapshot.nextSequence
            }
            throw error
        }

        state.withLock { Self.notifyGroupObservers(&$0) }
        return ids
    }

    @discardableResult
    public func updateTxStatus(
        for id: DurableTxId,
        expectedCurrentStatus: DurableTxStatus,
        verdict: Verdict
    ) async throws -> Bool {
        try state.withLock { current in
            guard let entry = current.entries[id], entry.status.isLive, entry.status == expectedCurrentStatus else {
                return false
            }

            let statusChanged = entry.status != verdict.status
            guard statusChanged || entry.successDetectedAt != verdict.successDetectedAt else { return false }

            try Self.mutate(&current, id) {
                $0.withStatus(verdict.status).withSuccessDetectedAt(verdict.successDetectedAt)
            }
            if statusChanged {
                for observer in current.statusObservers[id] ?? [] {
                    observer.yield(verdict.status)
                }
            }
            return true
        }
    }

    public func getAllEntries() async throws -> [DurableTxEntry] {
        allEntries
    }

    public func getAllEntries(domain: TxDomainId) async throws -> [DurableTxEntry] {
        allEntries.filter { $0.domainId == domain }
    }

    public func getEntry(id: DurableTxId) async throws -> DurableTxEntry? {
        state.withLock { $0.entries[id] }
    }

    public func subscribeStatus(id: DurableTxId) -> AnyAsyncSequence<DurableTxStatus> {
        AsyncStream<DurableTxStatus> { continuation in
            state.withLock { current in
                if let entry = current.entries[id] {
                    continuation.yield(entry.status)
                }
                current.statusObservers[id, default: []].append(continuation)
            }
        }
        .eraseToAnyAsyncSequence()
    }

    public func getGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) async throws -> [DurableTxEntry] {
        allEntries.filter { $0.domainId == domain && $0.groupId == groupId }
    }

    public func subscribeGroupEntries(
        domain: TxDomainId,
        groupId: DurableTxGroupId
    ) -> AnyAsyncSequence<[DurableTxEntry]> {
        let key = GroupKey(domain: domain, groupId: groupId)
        return AsyncStream<[DurableTxEntry]> { continuation in
            state.withLock { current in
                continuation.yield(Self.group(key, in: current))
                current.groupObservers[key, default: []].append(continuation)
            }
        }
        .eraseToAnyAsyncSequence()
    }
}

private extension InMemoryDurableTxRepository {
    static func sorted(_ entries: [DurableTxId: DurableTxEntry]) -> [DurableTxEntry] {
        entries.values.sorted { $0.sequence < $1.sequence }
    }

    static func group(_ key: GroupKey, in state: State) -> [DurableTxEntry] {
        sorted(state.entries).filter { $0.domainId == key.domain && $0.groupId == key.groupId }
    }

    static func notifyGroupObservers(_ state: inout State) {
        for (key, observers) in state.groupObservers {
            let snapshot = group(key, in: state)
            for observer in observers {
                observer.yield(snapshot)
            }
        }
    }

    static func mutate(
        _ state: inout State,
        _ id: DurableTxId,
        _ transform: (DurableTxEntry) -> DurableTxEntry
    ) throws {
        guard let entry = state.entries[id] else {
            throw DurableTxError.entryNotFound(id)
        }
        state.entries[id] = transform(entry)
        notifyGroupObservers(&state)
    }
}
