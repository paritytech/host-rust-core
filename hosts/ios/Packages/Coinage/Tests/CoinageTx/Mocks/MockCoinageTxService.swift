import Foundation
import os
import Operation_iOS
import ExtrinsicService
import AsyncExtensions
@testable import Coinage

/// Thread-safe journal for recording mock call events.
final class CallJournal: @unchecked Sendable {
    private let mutex = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var events: [String] = []
    }

    func record(_ event: String) {
        mutex.withLock { $0.events.append(event) }
    }

    var events: [String] {
        mutex.withLock { $0.events }
    }
}

actor MockCoinageTxService: CoinageTxServicing {
    let store: MockCoinageTxRepository
    let callJournal: CallJournal

    private(set) var submittedInputs: [[CoinageTxInput]] = []
    private(set) var submittedOutputs: [[OwnAsset]] = []
    private(set) var handoffAssets: [OwnAsset] = []
    private(set) var recoveryPassCount: Int = 0

    private let submissionOutcome: SubmissionOutcome

    enum SubmissionOutcome {
        /// Registration succeeds and the entry resolves to `finalizedSuccess`.
        case success
        /// Registration succeeds and the entry resolves to `failure`.
        case chainFailure
        /// `submit` throws before registering.
        case thrown
    }

    init(
        store: MockCoinageTxRepository = MockCoinageTxRepository(),
        callJournal: CallJournal = CallJournal(),
        submissionOutcome: SubmissionOutcome = .success
    ) {
        self.store = store
        self.callJournal = callJournal
        self.submissionOutcome = submissionOutcome
    }

    @discardableResult
    func submitTransactions(
        _ requests: [CoinageTxRequest],
        groupId _: CoinageTxGroupId?
    ) async throws -> [CoinageTxId] {
        var ids: [CoinageTxId] = []
        for request in requests {
            try await ids.append(recordSubmission(request))
        }
        return ids
    }

    private func recordSubmission(_ request: CoinageTxRequest) async throws -> CoinageTxId {
        submittedInputs.append(request.inputs)
        submittedOutputs.append(request.outputs)
        callJournal.record("submit")

        if case .thrown = submissionOutcome {
            throw StubError.boom
        }

        let entry = CoinageTxEntry(
            inputs: request.inputs,
            outputs: request.outputs,
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 0, hash: Data(repeating: 0, count: 32)),
            mortality: 300
        )
        try await store.register(entry)

        // Drive the entry to a terminal status so a caller awaiting the outcome via
        // `subscribeTransactionStatus` resolves immediately.
        let terminal: CoinageTxStatus =
            switch submissionOutcome {
            case .chainFailure: .failure
            case .success,
                 .thrown: .finalizedSuccess
            }
        try await store.updateStatus(entry.id, to: terminal)

        return entry.id
    }

    nonisolated func subscribeTransactionStatus(_ id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus> {
        store.subscribeStatus(id: id)
    }

    func getOperationGroupStatuses(_ groupId: CoinageTxGroupId) async throws -> [CoinageTxEntry] {
        try await store.getOperationGroupStatuses(groupId)
    }

    nonisolated func subscribeOperationGroupStatuses(
        _ groupId: CoinageTxGroupId
    ) -> AnyAsyncSequence<[CoinageTxEntry]> {
        store.subscribeOperationGroupStatuses(groupId)
    }

    nonisolated func startRecoveryPass() {
        Task { [weak self] in
            await self?.incrementRecoveryPassCount()
        }
    }

    nonisolated func start() {}

    nonisolated func stop() {}

    func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        callJournal.record("preCommitHandoff")
        handoffAssets.append(contentsOf: assets)
        try await store.precommitHandOff(assets) { _ in }
        return StoreHandoffCommit(assets: assets, store: store)
    }

    func releaseUncommittedHandoffs() async throws {
        try await store.releaseUncommittedHandoffs()
    }

    private func incrementRecoveryPassCount() {
        recoveryPassCount += 1
    }
}

enum StubError: Error {
    case boom
}
