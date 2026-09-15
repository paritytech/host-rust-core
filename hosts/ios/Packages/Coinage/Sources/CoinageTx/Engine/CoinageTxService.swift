import AsyncExtensions
import Foundation
import ExtrinsicService
import SDKLogger
import StructuredConcurrency
import SubstrateSdk
import os

/// The durability subsystem's public face.
public protocol CoinageTxServicing: Sendable {
    /// Registers several transactions atomically under one `groupId` — all commit or none do — then
    /// tracks each. Returns their ids in request order. A within-batch conflict rejects the whole
    /// batch and nothing is registered.
    @discardableResult
    func submitTransactions(
        _ requests: [CoinageTxRequest],
        groupId: CoinageTxGroupId?
    ) async throws -> [CoinageTxId]

    /// A stream of a submitted entry's status: the current value, then every change. Lets a caller
    /// that must not report success until the chain has — offboarding an external payment — await a
    /// terminal outcome after a fire-and-forget ``submit(inputs:outputs:builder:origin:)``.
    func subscribeTransactionStatus(_ id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus>

    /// Every entry registered under `groupId`, in registration order — a snapshot read for seeding a
    /// status before subscribing. Empty when the group has never been registered.
    func getOperationGroupStatuses(_ groupId: CoinageTxGroupId) async throws -> [CoinageTxEntry]

    /// A stream of the entries registered under `groupId`: the current set, then every change, in
    /// registration order. Lets a claim watch its whole group settle by `groupId = messageId`.
    func subscribeOperationGroupStatuses(_ groupId: CoinageTxGroupId) -> AnyAsyncSequence<[CoinageTxEntry]>

    /// Starts a recovery pass without waiting for it. Never awaited by startup: a single
    /// unresolvable entry must not hold the app for a mortality window.
    func startRecoveryPass()

    /// Starts the finalized-head trigger and runs one pass immediately.
    ///
    /// Subsumes ``startRecoveryPass()``: callers that only need the one-shot pass keep using that.
    func start()

    /// Cancels the finalized-head trigger. Safe to call when not started.
    func stop()

    /// Provisionally reserves `assets` against being spent again, before their keys reach the
    /// transport. The reservation is released on relaunch unless the returned handle is committed
    /// once the carrying payload is durable — so a payment that fails after this point never
    /// freezes the coins.
    func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit

    /// Clears the reservations of payments that never became durable. Runs once, on launch.
    func releaseUncommittedHandoffs() async throws
}

public extension CoinageTxServicing {
    /// Registers one transaction and starts tracking its extrinsic in the background, returning the
    /// entry's id as soon as it is committed — so the inputs are claimed before this returns, but
    /// the caller does not wait for inclusion. `groupId` labels the operation that registered it
    /// (e.g. a transfer's message id), or `nil` when ungrouped. Status is resolved by the tracker
    /// and the recovery pass; a caller that must await the outcome observes it via
    /// ``subscribeTransactionStatus(_:)``.
    ///
    /// The one-request case of ``submitTransactions(_:groupId:)``.
    @discardableResult
    func submitTransaction(request: CoinageTxRequest, groupId: CoinageTxGroupId?) async throws -> CoinageTxId {
        let ids = try await submitTransactions([request], groupId: groupId)
        guard let id = ids.first else {
            throw TransferStrategyError.submissionFailed(CancellationError())
        }
        return id
    }
}

/// Owns the entry set and everything that reads or writes it.
///
/// Not an actor: most stored properties are `let` and every method suspends on its first
/// statement, so actor isolation would protect nothing while implying a serialization it cannot
/// provide. Registration is serialized by the store's transaction, and `CoinageTrackingTxSet` carries
/// its own lock. The finalized-head trigger task handle is the one mutable piece of state,
/// guarded by a lock.
public final class CoinageTxService: @unchecked Sendable {
    private let store: any CoinageTxRepositoryProtocol
    private let registrar: CoinageTxRegistrar
    private let watcher: CoinageTxTracker
    private let pass: RecoveryPass
    private let operationFactory: any ExtrinsicOperationFactoryProtocol
    private let chainFactory: any CoinageChainViewFactoryProtocol
    private let logger: SDKLoggerProtocol?

    private let triggerTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    init(
        store: any CoinageTxRepositoryProtocol,
        registrar: CoinageTxRegistrar,
        watcher: CoinageTxTracker,
        pass: RecoveryPass,
        operationFactory: any ExtrinsicOperationFactoryProtocol,
        chainFactory: any CoinageChainViewFactoryProtocol,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.registrar = registrar
        self.watcher = watcher
        self.pass = pass
        self.operationFactory = operationFactory
        self.chainFactory = chainFactory
        self.logger = logger
    }
}

// MARK: - CoinageTxServicing

extension CoinageTxService: CoinageTxServicing {
    @discardableResult
    public func submitTransactions(
        _ requests: [CoinageTxRequest],
        groupId: CoinageTxGroupId?
    ) async throws -> [CoinageTxId] {
        // Build every extrinsic before registering any, so a build failure aborts before a single
        // extrinsic is broadcast. The batch then registers atomically; only then is each tracked.

        logger?.debug("Building requests: \(requests.count) groupId: \(String(describing: groupId))")

        let models = try await buildModels(requests)

        logger?.debug("Registering requests: \(requests.count) groupId: \(String(describing: groupId))")

        let registrations = try buildRegistrations(requests, models: models, groupId: groupId)

        let ids = try await registrar.register(registrations)

        logger?.debug("Starting tracking requests")

        for (id, model) in zip(ids, models) {
            track(model, transactionId: id)
        }

        return ids
    }

    public func subscribeTransactionStatus(_ id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus> {
        store.subscribeStatus(id: id)
    }

    public func getOperationGroupStatuses(_ groupId: CoinageTxGroupId) async throws -> [CoinageTxEntry] {
        try await store.getOperationGroupStatuses(groupId)
    }

    public func subscribeOperationGroupStatuses(
        _ groupId: CoinageTxGroupId
    ) -> AnyAsyncSequence<[CoinageTxEntry]> {
        store.subscribeOperationGroupStatuses(groupId)
    }

    public func startRecoveryPass() {
        Task { [pass] in
            await pass.run()
        }
    }

    public func start() {
        let task = Task { [pass, chainFactory] in
            await pass.run()

            // A pass on every newly finalized head and every new best head. Finality repairs
            // outputs a released watcher left `pendingMint`; the best head advances several
            // blocks earlier, so `pendingSuccess` is picked up promptly. Passes coalesce, so
            // frequent best-head ticks do not stack up.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await Self.runPass(on: chainFactory.finalizedHeads(), pass: pass) }
                group.addTask { await Self.runPass(on: chainFactory.bestHeads(), pass: pass) }
            }
        }
        let previous = triggerTask.withLock { current in
            let old = current
            current = task
            return old
        }
        previous?.cancel()
    }

    public func stop() {
        let task = triggerTask.withLock { current in
            let old = current
            current = nil
            return old
        }
        task?.cancel()
    }

    public func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        try await registrar.preCommitHandoff(assets)
    }

    public func releaseUncommittedHandoffs() async throws {
        try await store.releaseUncommittedHandoffs()
    }
}

// MARK: - Submission

private extension CoinageTxService {
    /// Builds and signs every request's extrinsic up-front, so each hash is known before
    /// registration. Requests sharing one signing `origin` are built in a single
    /// `buildExtrinsics` call so their nonces are sequential — required for dependent transactions
    /// where one spends another's output. Requests with distinct origins (e.g. per-recycler unload
    /// tokens) are built independently, since each carries its own signer. Order is preserved so the
    /// returned models align with `requests`.
    func buildModels(_ requests: [CoinageTxRequest]) async throws -> [ExtrinsicBuiltModel] {
        guard !requests.isEmpty else { return [] }

        // Groups have distinct signing origins, so their builds are independent — run them
        // concurrently rather than serialising one behind another. Results are re-assembled by
        // original request index below, so the returned order is deterministic regardless of which
        // group finishes first.
        let built = try await withThrowingTaskGroup(
            of: (indices: [Int], models: [ExtrinsicBuiltModel]).self
        ) { taskGroup in
            for group in groupBySharedOrigin(requests) {
                taskGroup.addTask {
                    try await (group, self.buildGroup(group, of: requests))
                }
            }

            var collected: [(indices: [Int], models: [ExtrinsicBuiltModel])] = []
            for try await result in taskGroup {
                collected.append(result)
            }
            return collected
        }

        var models = [ExtrinsicBuiltModel?](repeating: nil, count: requests.count)
        for entry in built {
            for (position, requestIndex) in entry.indices.enumerated() {
                models[requestIndex] = entry.models[position]
            }
        }

        return try models.map { model in
            guard let model else { throw TransferStrategyError.submissionFailed(CancellationError()) }
            return model
        }
    }

    /// Builds one same-origin group's extrinsics in a single indexed call, so their nonces are
    /// sequential — required for dependent transactions where one spends another's output.
    func buildGroup(_ group: [Int], of requests: [CoinageTxRequest]) async throws -> [ExtrinsicBuiltModel] {
        logger?.debug("Building \(group.count) extrinsic(s)")
        let built = try await operationFactory.buildExtrinsics(
            { builder, index in try requests[group[index]].builder(builder) },
            origin: requests[group[0]].origin,
            payingIn: nil,
            indexes: IndexSet(0 ..< group.count)
        ).asyncExecute()
        logger?.debug("Built \(built.count) extrinsic(s)")

        guard built.count == group.count else {
            throw TransferStrategyError.submissionFailed(CancellationError())
        }
        return built
    }

    /// Groups request indices by the identity of their signing `origin`, preserving first-seen and
    /// within-group order. Origins are reference types (`ExtrinsicCompoundOrigin`), so same-instance
    /// requests — a caller reusing one origin for a dependent batch — group together; distinct
    /// instances stay separate and are built on their own.
    func groupBySharedOrigin(_ requests: [CoinageTxRequest]) -> [[Int]] {
        var groups: [[Int]] = []
        var indexByOrigin: [ObjectIdentifier: Int] = [:]
        for (index, request) in requests.enumerated() {
            let key = ObjectIdentifier(request.origin as AnyObject)
            if let groupIndex = indexByOrigin[key] {
                groups[groupIndex].append(index)
            } else {
                indexByOrigin[key] = groups.count
                groups.append([index])
            }
        }
        return groups
    }

    /// Builds one registration per request. Both the checkpoint and the mortality window are read
    /// from the extrinsic's own `CheckMortality` era — the window the runtime will actually enforce,
    /// which is exactly what Rule 7 must search — rather than re-derived from the chain. The `txHash`
    /// is the up-front hash of the built extrinsic, so an entry is resolvable by Rule 7 even before
    /// tracking records anything.
    func buildRegistrations(
        _ requests: [CoinageTxRequest],
        models: [ExtrinsicBuiltModel],
        groupId: CoinageTxGroupId?
    ) throws -> [CoinageTxRegistration] {
        try zip(requests, models).map { request, model in
            guard let anchor = model.mortalityAnchorBlock, let period = model.mortalityPeriod else {
                throw CoinageTxError.notMortal
            }

            return try CoinageTxRegistration(
                txHash: Data(hexString: model.extrinsic).blake2b32(),
                checkpoint: BlockRef(number: anchor.blockNumber, hash: anchor.blockHash),
                mortalityBlocks: UInt32(period),
                groupId: groupId,
                inputs: request.inputs,
                outputs: request.outputs
            )
        }
    }

    /// Hands an already-built extrinsic to the tracker, wiring release-time recovery to the pass.
    func track(_ model: ExtrinsicBuiltModel, transactionId: CoinageTxId) {
        watcher.trackTransaction(model, transactionId: transactionId) { [pass] in
            Task { await pass.run() }
        }
    }
}

// MARK: - Head-driven passes

private extension CoinageTxService {
    /// Runs a pass on every head the stream yields. The factory's head streams are self-healing
    /// and never surface an error; a throw only means the stream ended, so there is nothing to do.
    static func runPass(on heads: AnyAsyncSequence<BlockNumber>, pass: RecoveryPass) async {
        do {
            for try await _ in heads {
                guard !Task.isCancelled else { break }
                await pass.run()
            }
        } catch {}
    }
}
