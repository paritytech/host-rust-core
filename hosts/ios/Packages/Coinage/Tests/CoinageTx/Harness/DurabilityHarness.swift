import Foundation
import os
@preconcurrency import ExtrinsicService
import SubstrateSdk
@testable import Coinage

/// Blocks a coinage extrinsic stays valid for by default in the harness.
let harnessMortalPeriod: UInt32 = 128

/// The whole durability subsystem over a ``FakeChain`` and an in-memory ledger.
///
/// It wires the *real* registrar, async submission tracker and recovery pass — exactly as
/// `CoinageService.make` does — over fakes, so the async submission path is exercised for real. The
/// one deviation from production is deliberate: the
/// tracker's release-time `onRecovery` only *records* a request rather than launching a pass, so
/// passes run only when a scenario asks — which keeps every walk replayable and shrinkable.
///
/// ``crash()`` is the point of the harness: it drops every volatile set (the watched set, the
/// registrar, the tracker, the pass) and builds the subsystem again over the same store, which is only
/// possible because no volatile state is global. ``relaunch()`` additionally releases uncommitted
/// handoff marks, the way a process start does.
final class DurabilityHarness: @unchecked Sendable {
    let chain: FakeChain
    let chainFactory: FakeCoinageChainViewFactory
    let store: MockCoinageTxRepository
    let submitter: FakeExtrinsicSubmitter
    private let backgroundExecutor = StubBackgroundExecutor()

    private var subsystem: Subsystem
    private var nextExtrinsicSeq: UInt64 = 0
    private let pendingSubmissions = OSAllocatedUnfairLock(initialState: [CoinageTxId]())

    init(
        initialState: CoinageChainState = .empty,
        submitter: FakeExtrinsicSubmitter = FakeExtrinsicSubmitter()
    ) {
        chain = FakeChain(initialState: initialState)
        chainFactory = FakeCoinageChainViewFactory(chain: chain)
        store = MockCoinageTxRepository()
        self.submitter = submitter
        subsystem = Subsystem.build(
            store: store,
            chainFactory: chainFactory,
            submitter: submitter,
            backgroundExecutor: backgroundExecutor
        )
    }

    /// Recovery being asked for is the observable half of a submission release.
    var recoveryRequestCount: Int { subsystem.recorder.count }

    /// Whether a live submission still owns the entry — the ledger lock a pass steps around.
    func isOwnedBySubmission(_ id: CoinageTxId) -> Bool { subsystem.watched.isWatched(id) }

    /// Reserves `assets` against being spent again, returning the commit handle. The two-phase form a
    /// scenario drives directly (``handOff(_:)`` is the pre-commit-and-commit shorthand).
    func preCommitHandoff(_ assets: [OwnAsset]) async throws -> any CoinageHandoffCommit {
        try await subsystem.registrar.preCommitHandoff(assets)
    }

    func crash() {
        subsystem = Subsystem.build(
            store: store,
            chainFactory: chainFactory,
            submitter: submitter,
            backgroundExecutor: backgroundExecutor
        )
        pendingSubmissions.withLock { $0.removeAll() }
    }

    /// What a relaunch does before anything else, so a scenario can model process start.
    func relaunch() async throws {
        crash()
        try await store.releaseUncommittedHandoffs()
    }

    // MARK: - Running the subsystem

    /// One recovery pass. Deterministic: nothing else launches a pass, so this is the only writer.
    func runPass() async {
        await subsystem.pass.run()
    }

    /// A pass with one read failing throughout it, so every evidence path has an unknown to handle.
    func runPass(withFault fault: FuzzFault) async {
        let healthy = chainFactory.faults
        chainFactory.faults = await faults(healthy, with: fault)
        // Not the fault-free `runPass`: a pass that cannot pin returns without a verdict, which is the
        // outcome this is here to produce.
        await subsystem.pass.run()
        chainFactory.faults = healthy
    }

    /// Runs the watchers to their release. A pass skips the entries submission still owns, so a
    /// scenario that wants the pass to decide has to get past this first. Awaits the real async
    /// tracker rather than advancing a virtual clock.
    func releaseSubmissions() async {
        let ids = pendingSubmissions.withLock { current -> [CoinageTxId] in
            let snapshot = current
            current.removeAll()
            return snapshot
        }
        guard !ids.isEmpty else { return }

        let watched = subsystem.watched
        var spins = 0
        while ids.contains(where: { watched.isWatched($0) }) {
            // Inside the loop, not once before it: a tracker's `Task` may not have reached
            // `submitAndSubscribe` (and parked its watch) yet when this is first called, so releasing
            // is retried every spin until the park exists and the emit lands — otherwise the tracker
            // waits out its silence timeout.
            submitter.releaseAll()
            await Task.yield()
            spins += 1
            if spins > 10_000 {
                try? await Task.sleep(nanoseconds: 100_000)
                spins = 0
            }
        }
        // Let the release-time `onRecovery` record run before returning, so a scenario can assert on it.
        await Task.yield()
        await Task.yield()
    }

    // MARK: - Extrinsic hashes

    /// A distinct extrinsic hash. Only distinctness matters — the body search looks an entry's hash up
    /// in block bodies, so two entries sharing bytes would find each other's blocks.
    func nextExtrinsicHash() -> Data {
        defer { nextExtrinsicSeq += 1 }
        var bytes = [UInt8](repeating: 0xEE, count: 32)
        var seq = nextExtrinsicSeq
        for offset in 0 ..< 8 {
            bytes[offset] = UInt8(truncatingIfNeeded: seq)
            seq >>= 8
        }
        return Data(bytes)
    }

    // MARK: - Registration

    /// Registers a batch atomically, tracks each through the real async tracker, and returns the ids.
    /// Callers usually follow with ``releaseSubmissions()`` before running a pass.
    @discardableResult
    func submit(_ registrations: [CoinageTxRegistration]) async throws -> [CoinageTxId] {
        let ids = try await subsystem.registrar.register(registrations)
        pendingSubmissions.withLock { $0.append(contentsOf: ids) }

        let recorder = subsystem.recorder
        let baseline = submitter.submissionCount
        for (id, registration) in zip(ids, registrations) {
            subsystem.tracker.trackTransaction(
                harnessBuiltModel(hex: registration.txHash.toHex(includePrefix: true)),
                transactionId: id
            ) { recorder.record() }
        }

        // Wait until the trackers have parked their watches, so submission index order matches
        // registration order — a watcher scenario keys its status streams by submission index.
        await awaitParked(untilCount: baseline + ids.count)
        return ids
    }

    private func awaitParked(untilCount target: Int) async {
        var spins = 0
        while submitter.submissionCount < target {
            await Task.yield()
            spins += 1
            if spins > 10_000 {
                try? await Task.sleep(nanoseconds: 100_000)
                spins = 0
            }
        }
    }

    /// A registration anchored at the current finalized head, which is what the registrar reads its
    /// window from.
    func registration(
        inputs: [CoinageTxInput],
        outputs: [OwnAsset],
        period: UInt32,
        groupId: CoinageTxGroupId? = nil
    ) -> CoinageTxRegistration {
        let finalized = chain.finalizedHead
        return CoinageTxRegistration(
            txHash: nextExtrinsicHash(),
            checkpoint: BlockRef(number: finalized.number, hash: finalized.hash),
            mortalityBlocks: period,
            groupId: groupId,
            inputs: inputs,
            outputs: outputs
        )
    }

    // MARK: - Handoff

    /// Pre-commits and commits a handoff of `assets`, returning whether it committed (a live claimant
    /// makes the pre-commit throw).
    @discardableResult
    func handOff(_ assets: [OwnAsset]) async -> Bool {
        do {
            let commit = try await subsystem.registrar.preCommitHandoff(assets)
            try await commit.commit()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Voucher / alias helpers

    /// The alias storage key the collector would ask for this voucher, derived from the chain exactly
    /// as it derives it — `nil` when the voucher is in no ring, so it has no alias key.
    func currentAliasKey(index: DerivationIndex) -> FakeAliasKey? {
        let member = HarnessKeys.voucherMemberKey(index)
        let state = chain.bestHead.state
        guard let exponent = state.recyclerMembers[member],
              let ringIndex = state.ringPositions[member]?.ringIndex
        else { return nil }
        return CoinageChainState.aliasKey(index: index, exponent: exponent, ringIndex: ringIndex)
    }

    // MARK: - Faults

    private func faults(_ base: ChainReadFaults, with fault: FuzzFault) async -> ChainReadFaults {
        var next = base
        switch fault {
        case .coins:
            next.statelessBlocks.formUnion([chain.finalizedHead.hash, chain.bestHead.hash])
        case .aliases:
            await next.unreadableAliases.formUnion(allCurrentAliasKeys())
        case .memberships:
            next.membershipsUnreadable = true
        case .ringPositions:
            next.ringPositionsUnreadable = true
        case .blocks:
            next.everyBlockUnreadable = true
        case .outcomes:
            let entries = await (try? store.getAllEntries()) ?? []
            next.unreadableOutcomes.formUnion(entries.map(\.txHash))
        case .pin:
            next.pinFails = true
        }
        return next
    }

    /// The current alias keys of every voucher any entry references, so an alias fault silences the
    /// reads a pass would actually make.
    private func allCurrentAliasKeys() async -> Set<FakeAliasKey> {
        let entries = await (try? store.getAllEntries()) ?? []
        let indices = entries.flatMap { entry -> [DerivationIndex] in
            let fromInputs = entry.inputs.compactMap { input -> DerivationIndex? in
                if case let .recyclerVoucher(index, _) = input { return index }
                return nil
            }
            let fromOutputs = entry.outputs.compactMap { output -> DerivationIndex? in
                if case let .recyclerVoucher(index, _) = output { return index }
                return nil
            }
            return fromInputs + fromOutputs
        }
        return Set(indices.compactMap { currentAliasKey(index: $0) })
    }
}

// MARK: - Subsystem

private extension DurabilityHarness {
    /// Records release-time recovery requests. Per-subsystem, so a crashed subsystem's stale tracker
    /// tasks cannot pollute the live counter.
    final class RecoveryRecorder: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: 0)
        func record() { lock.withLock { $0 += 1 } }
        var count: Int { lock.withLock { $0 } }
    }

    struct Subsystem {
        let watched: CoinageTrackingTxSet
        let registrar: CoinageTxRegistrar
        let tracker: CoinageTxTracker
        let pass: RecoveryPass
        let recorder: RecoveryRecorder

        static func build(
            store: MockCoinageTxRepository,
            chainFactory: FakeCoinageChainViewFactory,
            submitter: FakeExtrinsicSubmitter,
            backgroundExecutor: StubBackgroundExecutor
        ) -> Subsystem {
            let watched = CoinageTrackingTxSet()
            let recorder = RecoveryRecorder()
            let registrar = CoinageTxRegistrar(
                store: store,
                validator: CoinageTxRegistrationValidator(),
                watched: watched,
                logger: nil
            )
            let pass = RecoveryPass(store: store, chainFactory: chainFactory, watched: watched, logger: nil)
            let tracker = CoinageTxTracker(
                submitter: submitter,
                store: store,
                chainFactory: chainFactory,
                watched: watched,
                backgroundExecutor: backgroundExecutor,
                logger: nil
            )
            return Subsystem(watched: watched, registrar: registrar, tracker: tracker, pass: pass, recorder: recorder)
        }
    }
}
