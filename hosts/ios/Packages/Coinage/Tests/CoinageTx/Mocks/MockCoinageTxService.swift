import Foundation
import os
import Operation_iOS
import ExtrinsicService
import AsyncExtensions
@testable import Coinage
import DurableTransactions

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

    private let submissionOutcome: SubmissionOutcome
    private let beforeRegistration: (@Sendable () async throws -> Void)?

    enum SubmissionOutcome: Equatable {
        /// Registration succeeds and the entry resolves to `finalizedSuccess`.
        case success
        /// Registration succeeds and the entry resolves to `failure`.
        case chainFailure
        /// `submit` throws before registering.
        case thrown
        /// Durable custody committed, but the caller never receives the submission result.
        case registeredThenThrown
    }

    init(
        store: MockCoinageTxRepository = MockCoinageTxRepository(),
        callJournal: CallJournal = CallJournal(),
        submissionOutcome: SubmissionOutcome = .success,
        beforeRegistration: (@Sendable () async throws -> Void)? = nil
    ) {
        self.store = store
        self.callJournal = callJournal
        self.submissionOutcome = submissionOutcome
        self.beforeRegistration = beforeRegistration
    }

    @discardableResult
    func submitTransactions(
        _ requests: [CoinageTxRequest],
        groupId: CoinageTxGroupId?,
        custody: NativeTransferCustody?,
        authorization: (@Sendable () throws -> Void)?
    ) async throws -> [CoinageTxId] {
        if let custody {
            if case .thrown = submissionOutcome { throw StubError.boom }
            let registrations = requests.map {
                CoinageTxRegistration(
                    txHash: Data(repeating: 0xAB, count: 32),
                    checkpoint: BlockRef(number: 0, hash: Data(repeating: 0, count: 32)),
                    mortalityBlocks: 300, groupId: groupId, inputs: $0.inputs, outputs: $0.outputs
                )
            }
            try await beforeRegistration?()
            let ledger = store.ledger
            let ids = try await store.durable.register(registrations.map(\.durable)) { scope, ids in
                try ledger.registerAssets(
                    registrations.map(\.assets), for: ids, custody: custody, authorization: authorization, in: scope
                )
            }
            submittedInputs += requests.map(\.inputs)
            submittedOutputs += requests.map(\.outputs)
            handoffAssets += custody.assets
            if case .registeredThenThrown = submissionOutcome { throw StubError.boom }
            for id in ids {
                try await store.updateStatus(id, to: submissionOutcome == .chainFailure ? .failure : .finalizedSuccess)
            }
            return ids
        }
        var ids: [CoinageTxId] = []
        for request in requests {
            try await ids.append(recordSubmission(request, groupId: groupId))
        }
        return ids
    }

    func retainNativeTransfer(
        _ custody: NativeTransferCustody, authorization: @escaping @Sendable () throws -> Void
    ) async throws -> any CoinageHandoffCommit {
        try await store.ledger.retainNativeTransfer(custody, authorization: authorization)
        handoffAssets += custody.assets
        return StoreHandoffCommit(assets: custody.assets, ledger: store.ledger)
    }

    func retainedNativeTransfer(
        custodyId: String
    ) async throws -> (custody: NativeTransferCustody, handoffCommit: any CoinageHandoffCommit)? {
        guard let custody = try await store.ledger.retainedNativeTransfer(custodyId: custodyId) else { return nil }
        return (custody, StoreHandoffCommit(assets: custody.assets, ledger: store.ledger))
    }

    private func recordSubmission(_ request: CoinageTxRequest, groupId: CoinageTxGroupId?) async throws -> CoinageTxId {
        submittedInputs.append(request.inputs)
        submittedOutputs.append(request.outputs)
        callJournal.record("submit")

        if case .thrown = submissionOutcome {
            throw StubError.boom
        }

        let entry = CoinageTxEntry(
            inputs: request.inputs,
            outputs: request.outputs,
            groupId: groupId,
            txHash: Data(repeating: 0xAB, count: 32),
            checkpoint: BlockRef(number: 0, hash: Data(repeating: 0, count: 32)),
            mortality: 300
        )
        try await store.register(entry)
        if case .registeredThenThrown = submissionOutcome { throw StubError.boom }

        // Drive the entry to a terminal status so a caller awaiting the outcome via
        // `subscribeTransactionStatus` resolves immediately.
        let terminal: CoinageTxStatus =
            switch submissionOutcome {
            case .chainFailure: .failure
            case .success,
                 .thrown, .registeredThenThrown: .finalizedSuccess
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

    func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        callJournal.record("preCommitHandoff")
        handoffAssets.append(contentsOf: assets)
        try await store.precommitHandOff(assets) { context in
            try CoinageTxRegistrationValidator().validateHandoff(Set(assets.map(\.publicKey)), transaction: context)
        }
        return StoreHandoffCommit(assets: assets, ledger: store.ledger)
    }

    func releaseUncommittedHandoffs() async throws {
        try await store.releaseUncommittedHandoffs()
    }
}

enum StubError: Error {
    case boom
}
