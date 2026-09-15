import AsyncExtensions
import Foundation
import SubstrateSdk
@testable import Coinage

actor MockCoinageTxRepository: CoinageTxRepositoryProtocol {
    private var entries: [CoinageTxId: CoinageTxEntry] = [:]
    private var pendingMarks: Set<OwnAsset> = []
    private var committedMarks: Set<OwnAsset> = []
    private var nextSequence: Int64 = 1
    private var statusObservers: [CoinageTxId: [AsyncStream<CoinageTxStatus>.Continuation]] = [:]
    private var groupObservers: [CoinageTxGroupId: [AsyncStream<[CoinageTxEntry]>.Continuation]] = [:]

    var allEntries: [CoinageTxEntry] {
        sortedEntries
    }

    var handoffMarks: Set<OwnAsset> {
        pendingMarks.union(committedMarks)
    }

    /// Convenience for the many tests that register a prepared entry directly, keeping its id — the
    /// mock enforces the invariants inline (by public key), independent of the closure the real
    /// store runs.
    func register(_ entry: CoinageTxEntry) async throws {
        try insert(entry)
    }

    /// Atomic batch: on any failure the whole batch is rolled back, matching the store's single
    /// transaction. `insert` dedups within the batch too, since each is inserted before the next.
    func register(
        _ registrations: [CoinageTxRegistration],
        validation _: @escaping (any CoinageTxValidationContextProtocol) throws -> Void,
        onCommit: @escaping ([CoinageTxId]) -> Void
    ) async throws {
        let entriesSnapshot = entries
        let sequenceSnapshot = nextSequence
        do {
            var ids: [CoinageTxId] = []
            for registration in registrations {
                let id = CoinageTxId()
                try insert(registration.makeEntry(id: id, sequence: 0))
                ids.append(id)
            }
            onCommit(ids)
        } catch {
            entries = entriesSnapshot
            nextSequence = sequenceSnapshot
            throw error
        }
    }

    /// Inline invariant enforcement + monotonic sequence, shared by both register paths.
    private func insert(_ entry: CoinageTxEntry) throws {
        guard !entry.inputs.isEmpty || !entry.outputs.isEmpty else {
            throw CoinageTxError.emptyEntry
        }

        let mintedOutputs = Set(entries.values.flatMap { $0.outputs.map(\.publicKey) })
        if let duplicate = entry.outputs.first(where: { mintedOutputs.contains($0.publicKey) }) {
            throw CoinageTxError.outputNotFresh(duplicate.publicKey.toHex())
        }

        let claimedInputs = Set(
            entries.values
                .filter { $0.status != .failure }
                .flatMap { $0.inputs.map(\.publicKey) }
        )
        if let claimed = entry.inputs.first(where: { claimedInputs.contains($0.publicKey) }) {
            throw CoinageTxError.inputAlreadyClaimed(claimed.publicKey.toHex())
        }

        let markKeys = Set(handoffMarks.map(\.publicKey))
        if let marked = entry.inputs.first(where: { markKeys.contains($0.publicKey) }) {
            throw CoinageTxError.inputHandedOff(marked.publicKey.toHex())
        }

        entries[entry.id] = entry.withSequence(nextSequence)
        nextSequence += 1
        notifyGroupObservers()
    }

    /// Test-only convenience (the production protocol has only the compare-and-set `updateTxStatus`):
    /// forces a status and notifies observers, for setting up scenarios.
    func updateStatus(_ id: CoinageTxId, to status: CoinageTxStatus) async throws {
        try mutate(id) { $0.withStatus(status) }
        for observer in statusObservers[id] ?? [] {
            observer.yield(status)
        }
    }

    @discardableResult
    func updateTxStatus(
        for id: CoinageTxId,
        expectedCurrentStatus: CoinageTxStatus,
        verdict: Verdict
    ) async throws -> Bool {
        guard let current = entries[id], current.status.isLive, current.status == expectedCurrentStatus else {
            return false
        }

        let statusChanged = current.status != verdict.status
        guard statusChanged || current.successDetectedAt != verdict.successDetectedAt else { return false }

        try mutate(id) {
            $0.withStatus(verdict.status).withSuccessDetectedAt(verdict.successDetectedAt)
        }
        if statusChanged {
            for observer in statusObservers[id] ?? [] {
                observer.yield(verdict.status)
            }
        }
        return true
    }

    func getAllEntries() async throws -> [CoinageTxEntry] {
        sortedEntries
    }

    func getEntry(id: CoinageTxId) async throws -> CoinageTxEntry? {
        entries[id]
    }

    func getOperationGroupStatuses(_ groupId: CoinageTxGroupId) async throws -> [CoinageTxEntry] {
        sortedEntries.filter { $0.groupId == groupId }
    }

    nonisolated func subscribeOperationGroupStatuses(
        _ groupId: CoinageTxGroupId
    ) -> AnyAsyncSequence<[CoinageTxEntry]> {
        AsyncStream<[CoinageTxEntry]> { continuation in
            Task { await self.attachGroup(continuation, to: groupId) }
        }
        .eraseToAnyAsyncSequence()
    }

    nonisolated func subscribeStatus(id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus> {
        AsyncStream<CoinageTxStatus> { continuation in
            Task { await self.attach(continuation, to: id) }
        }
        .eraseToAnyAsyncSequence()
    }

    func minter(of asset: OwnAsset) async throws -> CoinageTxEntry? {
        entries.values.first { $0.outputs.contains(asset) }
    }

    func consumers(of input: CoinageTxInput) async throws -> [CoinageTxEntry] {
        sortedEntries.filter { $0.inputs.contains(input) }
    }

    /// Test helper: directly records a committed handoff mark (skips the two-phase flow).
    func markHandedOff(_ asset: OwnAsset) async throws {
        committedMarks.insert(asset)
    }

    func precommitHandOff(
        _ assets: [OwnAsset],
        validation _: @escaping (any CoinageTxValidationContextProtocol) throws -> Void
    ) async throws {
        for asset in assets where !committedMarks.contains(asset) {
            pendingMarks.insert(asset)
        }
    }

    func commitHandoffs(_ keys: [PublicKey]) async throws {
        let keySet = Set(keys)
        for asset in pendingMarks where keySet.contains(asset.publicKey) {
            pendingMarks.remove(asset)
            committedMarks.insert(asset)
        }
    }

    func releaseUncommittedHandoffs() async throws {
        pendingMarks.removeAll()
    }

    func handedOffCoins() async throws -> [OwnAsset] {
        Array(handoffMarks)
    }
}

private extension MockCoinageTxRepository {
    var sortedEntries: [CoinageTxEntry] {
        entries.values.sorted { $0.sequence < $1.sequence }
    }

    func attach(_ continuation: AsyncStream<CoinageTxStatus>.Continuation, to id: CoinageTxId) {
        if let entry = entries[id] {
            continuation.yield(entry.status)
        }
        statusObservers[id, default: []].append(continuation)
    }

    func attachGroup(_ continuation: AsyncStream<[CoinageTxEntry]>.Continuation, to groupId: CoinageTxGroupId) {
        continuation.yield(sortedEntries.filter { $0.groupId == groupId })
        groupObservers[groupId, default: []].append(continuation)
    }

    func notifyGroupObservers() {
        for (groupId, observers) in groupObservers {
            let snapshot = sortedEntries.filter { $0.groupId == groupId }
            for observer in observers {
                observer.yield(snapshot)
            }
        }
    }

    func mutate(_ id: CoinageTxId, _ transform: (CoinageTxEntry) -> CoinageTxEntry) throws {
        guard let entry = entries[id] else {
            throw CoinageTxError.entryNotFound(id)
        }
        entries[id] = transform(entry)
        notifyGroupObservers()
    }
}

private extension CoinageTxEntry {
    /// The immutable entry rebuilt with a new `sequence` — the mock assigns a monotonic sequence on
    /// insert the way the store does.
    func withSequence(_ sequence: Int64) -> CoinageTxEntry {
        CoinageTxEntry(
            id: id,
            sequence: sequence,
            inputs: inputs,
            outputs: outputs,
            groupId: groupId,
            txHash: txHash,
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: successDetectedAt,
            status: status,
            createdAt: createdAt
        )
    }
}
