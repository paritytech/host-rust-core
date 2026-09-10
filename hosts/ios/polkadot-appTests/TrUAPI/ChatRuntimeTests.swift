import Foundation
import os
import Testing
import Products
import UIKitExt
@testable import polkadot_app

// MARK: - Helpers

private final class FakeChatWorker: ProductChatWorking, @unchecked Sendable {
    struct Calls {
        var botStarted = 0
        var bound = 0
        var unbound = 0
        var lastUserMessage: (text: String, roomId: String?)?
        var disposed = 0
    }

    let calls = OSAllocatedUnfairLock(initialState: Calls())

    func dispose() async { calls.withLock { $0.disposed += 1 } }
    func bindMessaging(_: ProductsNativeApi.MessagingSupport) { calls.withLock { $0.bound += 1 } }
    func unbindMessaging() { calls.withLock { $0.unbound += 1 } }
    func onBotStarted() async throws { calls.withLock { $0.botStarted += 1 } }

    func onUserMessage(text: String, roomId: String?) async throws {
        calls.withLock { $0.lastUserMessage = (text, roomId) }
    }

    func renderMessage(
        messageId _: String,
        messageType _: String,
        messageData _: Data
    ) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func dispatchEvent(roomId _: String?, messageId _: String, actionId _: String, payload _: String?) async {}

    @MainActor func attach(presentationView _: ControllerBackedProtocol) {}
}

private final class FakeWorkerManager: ProductWorkerManaging, @unchecked Sendable {
    private let active = OSAllocatedUnfairLock(initialState: 0)
    private let worker: ProductChatWorking

    init(worker: ProductChatWorking) { self.worker = worker }

    var activeCount: Int { active.withLock { $0 } }

    func acquire(productId _: ProductId) async -> ProductWorkerLease {
        active.withLock { $0 += 1 }
        let token = ProductWorkerToken { [active] in active.withLock { $0 -= 1 } }
        return ProductWorkerLease(token: token, result: .success(worker))
    }
}

private func makeRustRuntime(
    execution: MockProductExecution = MockProductExecution(),
    chainConnections: MockChainConnections = MockChainConnections(),
    engine: MockJSEngine
) -> ChatRustRuntime {
    ChatRustRuntime(
        productUrl: URL(string: "product://test.dot/index.js")!,
        executionModel: makeExecutionModel(execution: execution, chainConnections: chainConnections),
        routers: ProductRoutersFacade.worker(),
        engineFactory: { engine }
    )
}

// MARK: - Tests

struct ChatRuntimeTests {
    @Test func nativeRuntimeStartBindsMessagingAndStartsBot() async throws {
        let worker = FakeChatWorker()
        let manager = FakeWorkerManager(worker: worker)
        let runtime = ManagedChatRuntime(productId: "test.dot", manager: manager)

        try await runtime.start(messagingSupport: .init(bot: nil, context: nil))

        #expect(worker.calls.withLock { $0.bound } == 1)
        #expect(worker.calls.withLock { $0.botStarted } == 1)
        #expect(manager.activeCount == 1)
    }

    @Test func nativeRuntimeForwardsUserMessage() async throws {
        let worker = FakeChatWorker()
        let manager = FakeWorkerManager(worker: worker)
        let runtime = ManagedChatRuntime(productId: "test.dot", manager: manager)

        try await runtime.onUserMessage(text: "hi", roomId: "r1")

        #expect(worker.calls.withLock { $0.lastUserMessage?.text } == "hi")
        #expect(worker.calls.withLock { $0.lastUserMessage?.roomId } == "r1")
    }

    @Test func nativeRuntimeDisposeUnbindsAndReleasesLock() async throws {
        let worker = FakeChatWorker()
        let manager = FakeWorkerManager(worker: worker)
        let runtime = ManagedChatRuntime(productId: "test.dot", manager: manager)

        try await runtime.start(messagingSupport: .init(bot: nil, context: nil))
        #expect(manager.activeCount == 1)

        await runtime.dispose()

        #expect(worker.calls.withLock { $0.unbound } == 1)
        #expect(manager.activeCount == 0)
    }

    @Test func rustRuntimeDisposeTearsDownExecutionOnce() async {
        let execution = MockProductExecution()
        let chainConnections = MockChainConnections()
        let runtime = makeRustRuntime(
            execution: execution,
            chainConnections: chainConnections,
            engine: MockJSEngine()
        )

        await runtime.dispose()
        await runtime.dispose()

        #expect(execution.stopWsBridgeCallCount == 1)
        #expect(execution.closeCallCount == 1)
        #expect(chainConnections.closeAllCallCount == 1)
    }

    @Test func rustRuntimeChatSeamsSurfaceCleanErrors() async {
        let runtime = makeRustRuntime(engine: MockJSEngine())

        await #expect(throws: (any Error).self) {
            try await runtime.onUserMessage(text: "hi", roomId: nil)
        }
    }

    @Test func rustRuntimeStartsBridgeAndEvaluatesBootstrapBeforeContainer() async throws {
        let execution = MockProductExecution()
        let engine = MockJSEngine()
        let runtime = makeRustRuntime(execution: execution, engine: engine)

        try await runtime.start(messagingSupport: .init(bot: nil, context: nil))

        #expect(execution.startWsBridgeCallCount == 1)

        // "truapi-native-ready" marks the bootstrap; "freezeAndDelete" the container.
        let bootstrapIndex = try #require(
            engine.evaluatedScripts.firstIndex { $0.contains("truapi-native-ready") }
        )
        let containerIndex = try #require(
            engine.evaluatedScripts.firstIndex { $0.contains("freezeAndDelete") }
        )
        #expect(bootstrapIndex < containerIndex)

        await runtime.dispose()
    }

    @Test func chatScriptsFactoryOrdersBootstrapBeforeContainer() throws {
        let factory = ChatRustRuntimeScriptsFactory(bootstrapScript: "/*bootstrap*/")

        let scripts = try factory.makeScripts()

        #expect(scripts.count == 2)
        #expect(scripts[0] == "/*bootstrap*/")
        #expect(scripts[1].contains("__truapi_localhost"))
    }
}
