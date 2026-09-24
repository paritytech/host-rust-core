import Foundation
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

/// The core counts worker references and reports only the transitions across
/// zero, so the supervisor must be exact: a worker left running burns a web
/// view, and one left half-booted swallows every later start.
struct PocketWorkerSupervisorTests {
    @Test
    func startsTheWorkerOnTheFirstDemand() async throws {
        let builder = StubBuilder()
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(builder.built == ["game.paseo"])
        #expect(supervisor.currentExecution(of: "game.paseo") != nil)
    }

    /// The core reports only transitions across zero, but a stop and a start can
    /// overtake each other; a second start while one is running must not open a
    /// second execution for the same product.
    @Test
    func doesNotStartASecondWorkerForTheSameProduct() async throws {
        let builder = StubBuilder()
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()
        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(builder.built == ["game.paseo"])
    }

    @Test
    func stopsTheWorkerAndForgetsItsExecution() async throws {
        let builder = StubBuilder()
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()
        supervisor.demandChanged(productId: "game.paseo", transition: .stop)
        try await settle()

        #expect(supervisor.currentExecution(of: "game.paseo") == nil)
    }

    /// A worker whose engine fails once it is already in the running map must
    /// leave nothing behind: the core keeps counting the reference the card
    /// holds, so no further stop arrives to clear a half-started entry, and
    /// every later start would be swallowed by the entry that is still there.
    @Test
    func leavesNothingBehindWhenTheEngineFailsToBoot() async throws {
        let builder = StubBuilder(engineFails: true)
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(supervisor.currentExecution(of: "game.paseo") == nil)

        builder.engineFails = false
        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(supervisor.currentExecution(of: "game.paseo") != nil)
    }

    /// A product with no Pocket worker cannot be built at all, which must be as
    /// clean a failure as one that breaks while booting.
    @Test
    func leavesNothingBehindWhenTheWorkerCannotBeBuilt() async throws {
        let builder = StubBuilder(cannotBuild: true)
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(supervisor.currentExecution(of: "game.paseo") == nil)

        builder.cannotBuild = false
        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(supervisor.currentExecution(of: "game.paseo") != nil)
    }

    /// A stop for a product that never started is what the core sends when a
    /// card's worker was refused, and it must not tear anything else down.
    @Test
    func ignoresAStopForAWorkerThatNeverStarted() async throws {
        let builder = StubBuilder()
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()
        supervisor.demandChanged(productId: "other.paseo", transition: .stop)
        try await settle()

        #expect(supervisor.currentExecution(of: "game.paseo") != nil)
    }

    /// The worker's card list is served from the bridge's snapshot, and the
    /// script that subscribes to it comes up inside `runtime.start()`. A
    /// snapshot filled after that point leaves the product reading an empty
    /// Pocket for the whole life of its worker.
    @Test
    func fillsTheCardListBeforeTheWorkersScriptComesUp() async throws {
        let builder = StubBuilder()
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(builder.cardsWhenTheEngineBooted.map(\.cardId) == ["loyalty"])
    }

    /// Republishing reads the execution back out of the published map, so a
    /// republish that ran before the execution was published reached nobody —
    /// and the bridge, whose snapshot had already moved, never sent another.
    @Test
    func tellsTheCoreWhatTheWorkerHoldsOnceItsExecutionIsPublished() async throws {
        let builder = StubBuilder()
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()

        #expect(builder.execution?.pocketCardNotifications.last?.map(\.cardId) == ["loyalty"])
    }

    /// Reading the collection waits on the network's dotNS suffix, which is a
    /// chain read on first use — exactly when two cards for one product scroll
    /// into view together. Actors are reentrant, so both starts reach the guard
    /// while the first is still waiting on it: two workers for one product is
    /// two headless web views, and only the last is ever stopped.
    @Test
    func doesNotStartASecondWorkerWhenTwoDemandsOverlap() async throws {
        let builder = StubBuilder()
        let supervisor = PocketWorkerSupervisor(
            builder: builder,
            pocket: pocketHolding([loyalty], tldDelay: .milliseconds(30))
        )

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()
        try await Task.sleep(for: .milliseconds(200))

        #expect(builder.built == ["game.paseo"])
    }

    /// A stop that lands while the worker is still being built finds nothing to
    /// remove, and the boot then publishes an execution no stop can reach: the
    /// web view and its chain connections run for the rest of the session.
    @Test
    func disposesAWorkerThatWasStoppedWhileItWasStillBooting() async throws {
        let builder = StubBuilder(buildDelay: .milliseconds(80))
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocketHolding([loyalty]))

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await Task.sleep(for: .milliseconds(20))
        supervisor.demandChanged(productId: "game.paseo", transition: .stop)
        try await settle()
        try await Task.sleep(for: .milliseconds(300))

        #expect(supervisor.currentExecution(of: "game.paseo") == nil)
        #expect(builder.execution?.closeCallCount == 1)
    }

    /// The supervisor follows the collection for the whole life of the process,
    /// and a worker already running is only told about a card added later
    /// because of that. Without it a product's own list silently goes stale the
    /// moment its worker is up.
    @Test
    func tellsARunningWorkerAboutACardAddedLater() async throws {
        let builder = StubBuilder()
        let repository = InMemoryPocketCardRepository([loyalty])
        let pocket = PocketFacade(tld: { "paseo" }, repository: repository)
        let supervisor = PocketWorkerSupervisor(builder: builder, pocket: pocket)

        supervisor.demandChanged(productId: "game.paseo", transition: .start)
        try await settle()
        #expect(try builder.bridge?.listCards().map(\.cardId) == ["loyalty"])

        await repository.insert(streak, face: .nil)
        pocket.collectionChanged()
        try await settle()

        #expect(try builder.bridge?.listCards().map(\.cardId).sorted() == ["loyalty", "streak"])
    }
}

// MARK: - Fixtures

private let loyalty = PocketCardEntry(
    key: PocketCardKey(productId: "game.paseo", cardId: PocketCardId(value: "loyalty")),
    title: "Loyalty",
    privileged: false
)

private let streak = PocketCardEntry(
    key: PocketCardKey(productId: "game.paseo", cardId: PocketCardId(value: "streak")),
    title: "Streak",
    privileged: false
)

/// The supervisor hands its work to a task, so the assertions wait for it
/// rather than for a fixed time.
private func settle() async throws {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(20))
}

/// `tldDelay` stands in for the chain read the suffix costs on first use, which
/// is the window two overlapping starts land in.
private func pocketHolding(_ cards: [PocketCardEntry], tldDelay: Duration = .zero) -> PocketFacade {
    PocketFacade(
        tld: {
            if tldDelay > .zero { try? await Task.sleep(for: tldDelay) }
            return "paseo"
        },
        repository: InMemoryPocketCardRepository(cards)
    )
}

private final class StubBuilder: PocketWorkerBuilding, @unchecked Sendable {
    private(set) var built: [ProductId] = []
    /// The execution of the worker built last, so a test can read what the core
    /// was told through it.
    private(set) var execution: MockProductExecution?
    /// What the bridge would have answered the moment the worker's engine came
    /// up, which is when its script subscribes to the card list.
    private(set) var cardsWhenTheEngineBooted: [PocketCard] = []
    /// The bridge of the worker built last, so a test can read the slice the
    /// core is being served after the collection moves.
    private(set) var bridge: ProductPocketHostBridge?

    var cannotBuild: Bool
    var engineFails: Bool
    private let buildDelay: Duration

    init(cannotBuild: Bool = false, engineFails: Bool = false, buildDelay: Duration = .zero) {
        self.cannotBuild = cannotBuild
        self.engineFails = engineFails
        self.buildDelay = buildDelay
    }

    func makeRuntime(productId: ProductId, pocket: ProductPocketHostBridge) async throws -> PocketWorkerRuntime {
        if cannotBuild { throw PocketWorkerError.noPocketWorker(productId) }
        if buildDelay > .zero { try await Task.sleep(for: buildDelay) }

        bridge = pocket

        built.append(productId)
        let execution = MockProductExecution()
        self.execution = execution

        let engineFails = engineFails
        return PocketWorkerRuntime(
            productUrl: URL(string: "https://product.invalid/worker.js")!,
            executionModel: RustRuntimeEnvironment.ExecutionModel(
                execution: execution,
                chainConnections: MockChainConnections(),
                osPermissionAsker: OSPermissionAsker()
            ),
            engineFactory: { [weak self] in
                self?.cardsWhenTheEngineBooted = (try? pocket.listCards()) ?? []
                return engineFails ? FailingJSEngine() as JSEngineProtocol : MockJSEngine()
            }
        )
    }
}

/// An engine whose page never comes up, which is what a worker archive that
/// cannot be loaded looks like from here.
private final class FailingJSEngine: JSEngineProtocol, @unchecked Sendable {
    func getState() async -> JSEngineState { .error("no page") }
    func initialize(with _: [JSEngineScript]) async throws { throw ScriptExecutorError.engineInitFailed }
    func evaluate(_: String) async throws -> Any? { nil }
    func registerFunction(name _: String, handler _: @escaping JSNativeHandler) async {}
    func dispatchEvent(actionId _: String, payload _: String) async throws {}
    func destroy() async {}
    func registerJSDeviceCapabilityHandler(_: @escaping JSDeviceCapabilityHandler) async {}
}
