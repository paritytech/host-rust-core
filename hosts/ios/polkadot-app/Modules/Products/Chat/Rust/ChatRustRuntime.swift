import Foundation
import Products
import TrUAPIHost
import UIKitExt

/// Rust chat runtime: the TrUAPI core handles product requests over its
/// localhost ws-bridge. Chat-environment seams (user messages, widget
/// rendering) are not wired in this milestone and surface clean errors.
///
/// An actor so `start`/`dispose` never race on runtime state. Actors are
/// reentrant, so `dispose()` can interleave while `start` is suspended:
/// `dispose` flips `disposed` before its first await and `start` re-checks
/// it after every await, destroying anything it created in the gap.
actor ChatRustRuntime: ChatRuntimeProtocol {
    enum ChatSeamError: Error {
        case notSupported(String)
    }

    private let productUrl: URL
    private let executionModel: RustRuntimeEnvironment.ExecutionModel
    // Set once in init and only read from the MainActor-isolated `attach`;
    // all facade mutation happens behind its own @MainActor method.
    private nonisolated(unsafe) let routers: ProductRoutersFacadeProtocol
    private let engineFactory: @Sendable () -> JSEngineProtocol
    private let logger: LoggerProtocol

    private var engine: JSEngineProtocol?
    private var engineMonitor: JSEngineMonitor?
    private var moduleBridge: JSESModuleBridge?
    private var started = false
    private var disposed = false

    init(
        productUrl: URL,
        executionModel: RustRuntimeEnvironment.ExecutionModel,
        routers: ProductRoutersFacadeProtocol,
        engineFactory: @Sendable @escaping () -> JSEngineProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.productUrl = productUrl
        self.executionModel = executionModel
        self.routers = routers
        self.engineFactory = engineFactory
        self.logger = logger
    }

    deinit {
        // Locals first: assert's and &&'s autoclosures are nonisolated;
        // direct reads of the (Sendable) stored properties are only legal
        // in the deinit body itself.
        let started = started
        let disposed = disposed
        assert(!started || disposed, "ChatRustRuntime dropped without dispose()")
    }

    func start(messagingSupport _: ProductsNativeApi.MessagingSupport) async throws {
        // Single-shot: a second start would re-activate the session with no
        // matching teardown; a post-dispose start must not run at all.
        guard !started, !disposed else { throw CancellationError() }
        started = true

        let jsEngine = try await bootEngine()

        try checkNotDisposed()
        let bootstrapScript = try await executionModel.startBridge()
        let scriptsFactory = ChatRustRuntimeScriptsFactory(bootstrapScript: bootstrapScript)

        // Factory order is load-bearing: the bootstrap publishes
        // __truapi_localhost, then the container lockdown gates WebSocket to
        // exactly that URL.
        for script in try scriptsFactory.makeScripts() {
            try checkNotDisposed()
            try await jsEngine.evaluate(script)
        }

        let modBridge = JSESModuleBridge(engine: jsEngine)
        await modBridge.install()

        try checkNotDisposed()
        moduleBridge = modBridge

        try await modBridge.executeScript(url: productUrl)

        logger.debug("Rust chat runtime started for: \(productUrl)")
    }

    func onUserMessage(text _: String, roomId _: String?) async throws {
        throw ChatSeamError.notSupported("user-message dispatch is not wired in rust mode yet")
    }

    func renderMessage(
        messageId _: String,
        messageType _: String,
        messageData _: Data
    ) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: ChatSeamError.notSupported("widget rendering is not wired in rust mode yet")
            )
        }
    }

    func dispatchEvent(roomId _: String?, messageId _: String, actionId: String, payload _: String?) async {
        logger.warning("Rust chat runtime: dropping event \(actionId) — chat seams not wired yet")
    }

    @MainActor
    func attach(presentationView view: ControllerBackedProtocol) {
        routers.setPresentationView(view)
    }

    func dispose() async {
        guard !disposed else { return }
        // Flipped before the first suspension: any start resuming after this
        // point observes it and unwinds.
        disposed = true

        await destroyEngineResources()

        executionModel.execution.stopWsBridge()
        executionModel.execution.close()
        executionModel.chainConnections.closeAll()

        logger.debug("Rust chat runtime disposed for: \(productUrl)")
    }
}

private extension ChatRustRuntime {
    func bootEngine() async throws -> JSEngineProtocol {
        let jsEngine = engineFactory()
        try await jsEngine.initialize()

        guard await jsEngine.getState() == .ready else {
            throw ScriptExecutorError.engineInitFailed
        }

        // Disposed while booting: dispose captured nil for the engine, so
        // this start is the only owner left — destroy before bailing.
        guard !disposed else {
            await jsEngine.destroy()
            throw CancellationError()
        }

        let monitor = JSEngineMonitor(
            engine: jsEngine,
            pauseEvent: .willResignActive,
            resumeEvent: .didBecomeActive
        )
        monitor.start()
        engineMonitor = monitor

        engine = jsEngine
        return jsEngine
    }

    func destroyEngineResources() async {
        engineMonitor?.stop()
        engineMonitor = nil

        let moduleBridge = moduleBridge
        self.moduleBridge = nil
        await moduleBridge?.dispose()

        let engine = engine
        self.engine = nil
        await engine?.destroy()
    }

    func checkNotDisposed() throws {
        guard !disposed else { throw CancellationError() }
    }
}
