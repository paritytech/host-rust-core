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
}

// MARK: - Fixtures

private let loyalty = PocketCardEntry(
    key: PocketCardKey(productId: "game.paseo", cardId: PocketCardId(value: "loyalty")),
    title: "Loyalty",
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

private func pocketHolding(_ cards: [PocketCardEntry]) -> PocketFacade {
    PocketFacade(tld: { "paseo" }, repository: InMemoryPocketCardRepository(cards))
}

private final class StubBuilder: PocketWorkerBuilding, @unchecked Sendable {
    private(set) var built: [ProductId] = []
    var cannotBuild: Bool
    var engineFails: Bool

    init(cannotBuild: Bool = false, engineFails: Bool = false) {
        self.cannotBuild = cannotBuild
        self.engineFails = engineFails
    }

    func makeRuntime(productId: ProductId, pocket _: ProductPocketHostBridge) async throws -> PocketWorkerRuntime {
        if cannotBuild { throw PocketWorkerError.noPocketWorker(productId) }

        built.append(productId)
        let engineFails = engineFails
        return PocketWorkerRuntime(
            productUrl: URL(string: "https://product.invalid/worker.js")!,
            executionModel: RustRuntimeEnvironment.ExecutionModel(
                execution: MockProductExecution(),
                chainConnections: MockChainConnections(),
                osPermissionAsker: OSPermissionAsker()
            ),
            engineFactory: { engineFails ? FailingJSEngine() as JSEngineProtocol : MockJSEngine() }
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
