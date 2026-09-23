import AsyncExtensions
import BackgroundExecution
@preconcurrency import ExtrinsicService
import Foundation
import os
@preconcurrency import SDKLogger
import StructuredConcurrency
import SubstrateSdk

/// Owns one fact: the status of every submitted transaction, for every domain.
///
/// Whatever a domain locks for a transaction it keeps itself, written through the registration hook.
/// This service never reads chain state of its own beyond block bodies and the heads — anything
/// domain-shaped reaches it only through that domain's ``TxCompletionOracle``.
public protocol DurableTxServicing: Sendable {
    /// Where a domain registers its oracle before it submits anything.
    var oracles: TxCompletionOracleRegistry { get }

    /// Builds, registers and submits several transactions as one operation: either all of them are
    /// recorded or none is. `onRegister` runs inside the registration transaction with the minted ids,
    /// so a domain's own rows commit together with the engine's. Returns once committed, which is before
    /// the bytes reach the wire: no extrinsic is ever in flight without a record.
    @discardableResult
    func submitTransactions(
        domain: TxDomainId,
        requests: [DurableTxRequest],
        groupId: DurableTxGroupId?,
        onRegister: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId]

    /// A stream of a transaction's status: the current value, then every change.
    func subscribeTransactionStatus(_ id: DurableTxId) -> AnyAsyncSequence<DurableTxStatus>

    /// Every transaction registered under `groupId`, in registration order. Empty when nothing was ever
    /// registered under it.
    func getGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) async throws -> [DurableTxEntry]

    /// A stream of the transactions registered under `groupId`: the current set, then every change.
    func subscribeGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) -> AnyAsyncSequence<[DurableTxEntry]>

    /// Starts a recovery pass without waiting for it. Never awaited by startup: a single unresolvable
    /// transaction must not hold the app for a mortality window.
    func startRecoveryPass()

    /// Runs one pass immediately, then a pass on every new head of every chain a registered domain lives
    /// on. Subsumes ``startRecoveryPass()``. Idempotent: a second call replaces the running loop, so a
    /// domain that registers its oracle after the loop started calls this again to have its chain watched.
    func start()

    /// Cancels the head-driven passes for every domain — the engine is shared. Safe to call when not
    /// started.
    func stop()
}

/// Orchestrates registration, submission tracking and the recovery pass, and exposes the queries.
///
/// Not an actor: most stored properties are `let` and every method suspends on its first statement, so
/// actor isolation would protect nothing. Registration is serialized by the store's transaction, and
/// ``DurableTxOwnershipSet`` carries its own lock. The head-driven task handle is the one mutable piece of
/// state, guarded by a lock.
public final class DurableTxService: DurableTxServicing, @unchecked Sendable {
    public let oracles: TxCompletionOracleRegistry

    private let store: any DurableTxRepositoryProtocol
    private let registrar: DurableTxRegistrar
    private let tracker: DurableTxTracker
    private let pass: DurableRecoveryPass
    private let chainFactory: any PinnedChainViewFactoryProtocol
    private let chainTools: any DurableChainToolsProviding
    private let logger: SDKLoggerProtocol?

    private let triggerTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    public init(
        store: any DurableTxRepositoryProtocol,
        registrar: DurableTxRegistrar,
        tracker: DurableTxTracker,
        pass: DurableRecoveryPass,
        oracles: TxCompletionOracleRegistry,
        chainFactory: any PinnedChainViewFactoryProtocol,
        chainTools: any DurableChainToolsProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.store = store
        self.registrar = registrar
        self.tracker = tracker
        self.pass = pass
        self.oracles = oracles
        self.chainFactory = chainFactory
        self.chainTools = chainTools
        self.logger = logger
    }

    /// Wires the engine over a store and the chain-bound seams.
    public static func make(
        store: any DurableTxRepositoryProtocol,
        chainViewFactory: any PinnedChainViewFactoryProtocol,
        chainTools: any DurableChainToolsProviding,
        backgroundExecutor: any BackgroundExecuting,
        logger: SDKLoggerProtocol?
    ) -> DurableTxService {
        let owned = DurableTxOwnershipSet()
        let oracles = TxCompletionOracleRegistry()

        return DurableTxService(
            store: store,
            registrar: DurableTxRegistrar(store: store, owned: owned, logger: logger),
            tracker: DurableTxTracker(
                store: store,
                chainFactory: chainViewFactory,
                owned: owned,
                backgroundExecutor: backgroundExecutor,
                logger: logger
            ),
            pass: DurableRecoveryPass(
                store: store,
                chainFactory: chainViewFactory,
                owned: owned,
                oracles: oracles,
                logger: logger
            ),
            oracles: oracles,
            chainFactory: chainViewFactory,
            chainTools: chainTools,
            logger: logger
        )
    }
}

// MARK: - DurableTxServicing

public extension DurableTxService {
    @discardableResult
    func submitTransactions(
        domain: TxDomainId,
        requests: [DurableTxRequest],
        groupId: DurableTxGroupId?,
        onRegister: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        guard let chainId = oracles.chainId(for: domain) else {
            throw DurableTxError.unregisteredDomain(domain)
        }

        let operationFactory = try await chainTools.extrinsicOperationFactory(for: chainId)
        let submitter = try await chainTools.extrinsicSubmitter(for: chainId)

        // Build every extrinsic before registering any, so a build failure aborts before a single
        // extrinsic is broadcast. The batch then registers atomically; only then is each tracked.
        logger?.debug("Building \(requests.count) request(s) domain: \(domain) groupId: \(String(describing: groupId))")

        let builder = ExtrinsicBatchBuilder(operationFactory: operationFactory, logger: logger)
        let models = try await builder.build(requests)

        let registrations = try Self.registrations(domain: domain, groupId: groupId, models: models)
        let ids = try await registrar.register(registrations, onRegister: onRegister)

        logger?.debug("Registered transactions=\(ids.count) groupId=\(String(describing: groupId))")

        for (id, model) in zip(ids, models) {
            let submission = DurableTxTracker.Submission(
                model: model,
                transactionId: id,
                chainId: chainId,
                submitter: submitter
            )
            tracker.track(submission) { [pass] in
                Task { await pass.run() }
            }
        }

        return ids
    }

    func subscribeTransactionStatus(_ id: DurableTxId) -> AnyAsyncSequence<DurableTxStatus> {
        store.subscribeStatus(id: id)
    }

    func getGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) async throws -> [DurableTxEntry] {
        try await store.getGroupEntries(domain: domain, groupId: groupId)
    }

    func subscribeGroupEntries(
        domain: TxDomainId,
        groupId: DurableTxGroupId
    ) -> AnyAsyncSequence<[DurableTxEntry]> {
        store.subscribeGroupEntries(domain: domain, groupId: groupId)
    }

    func startRecoveryPass() {
        Task { [pass] in
            await pass.run()
        }
    }

    func start() {
        let chainIds = oracles.chainIds

        let task = Task { [pass, chainFactory] in
            await pass.run()

            // A pass on every newly finalized head and every new best head of every watched chain.
            // Finality repairs what a released watcher left pending; the best head advances several
            // blocks earlier, so `pendingSuccess` is picked up promptly. Passes coalesce, so frequent
            // best-head ticks do not stack up.
            await withTaskGroup(of: Void.self) { group in
                for chainId in chainIds {
                    group.addTask { await Self.runPass(on: chainFactory.finalizedHeads(chainId: chainId), pass: pass) }
                    group.addTask { await Self.runPass(on: chainFactory.bestHeads(chainId: chainId), pass: pass) }
                }
            }
        }
        let previous = triggerTask.withLock { current in
            let old = current
            current = task
            return old
        }
        previous?.cancel()
    }

    func stop() {
        let task = triggerTask.withLock { current in
            let old = current
            current = nil
            return old
        }
        task?.cancel()
    }
}

// MARK: - Registration

private extension DurableTxService {
    /// Builds one registration per built extrinsic. Both the checkpoint and the mortality window are read
    /// from the extrinsic's own `CheckMortality` era — the window the runtime will actually enforce, which
    /// is exactly what the body search must cover — rather than re-derived from the chain. The `txHash`
    /// is the up-front hash of the built extrinsic, so a transaction is resolvable by the search even
    /// before tracking records anything.
    static func registrations(
        domain: TxDomainId,
        groupId: DurableTxGroupId?,
        models: [ExtrinsicBuiltModel]
    ) throws -> [DurableTxRegistration] {
        try models.map { model in
            guard let anchor = model.mortalityAnchorBlock, let period = model.mortalityPeriod else {
                throw DurableTxError.notMortal
            }

            return try DurableTxRegistration(
                domainId: domain,
                groupId: groupId,
                txHash: Data(hexString: model.extrinsic).blake2b32(),
                checkpoint: BlockRef(number: anchor.blockNumber, hash: anchor.blockHash),
                mortalityBlocks: UInt32(period)
            )
        }
    }
}

// MARK: - Head-driven passes

private extension DurableTxService {
    /// Runs a pass on every head the stream yields. The factory's head streams are self-healing and never
    /// surface an error; a throw only means the stream ended, so there is nothing to do.
    static func runPass(on heads: AnyAsyncSequence<BlockNumber>, pass: DurableRecoveryPass) async {
        do {
            for try await _ in heads {
                guard !Task.isCancelled else { break }
                await pass.run()
            }
        } catch {}
    }
}
