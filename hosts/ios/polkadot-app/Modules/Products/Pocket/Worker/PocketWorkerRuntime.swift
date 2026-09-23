import Foundation
import Products
import TrUAPIHost

/// One product's worker, running headless behind a Worker execution.
///
/// The script runs in a web view with no screen of its own: the bootstrap
/// publishes the execution's loopback bridge before the page exists, the entry
/// module connects to it, and everything the worker draws comes back over the
/// execution rather than through any view.
///
/// An actor so `start` and `dispose` never race. Actors are reentrant, so
/// `dispose` flips `disposed` before its first await and `start` re-checks it
/// after every one: a half-booted worker left behind would swallow every later
/// start while the core keeps counting the reference its card holds.
actor PocketWorkerRuntime {
    private let productUrl: URL
    private let executionModel: RustRuntimeEnvironment.ExecutionModel
    private let engineFactory: @Sendable () -> JSEngineProtocol
    private let logger: LoggerProtocol

    private var engine: JSEngineProtocol?
    private var moduleBridge: JSESModuleBridge?
    private var disposed = false

    init(
        productUrl: URL,
        executionModel: RustRuntimeEnvironment.ExecutionModel,
        engineFactory: @escaping @Sendable () -> JSEngineProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.productUrl = productUrl
        self.executionModel = executionModel
        self.engineFactory = engineFactory
        self.logger = logger
    }

    nonisolated var execution: TrUAPIProductExecutionProtocol { executionModel.execution }

    func start() async throws {
        try checkNotDisposed()

        let bootstrap = try executionModel.startBridge()
        let scripts = try RustRuntimeScriptsFactory(bootstrapScript: bootstrap).makeScripts()
        let jsEngine = try await bootEngine(scripts: scripts)

        let bridge = JSESModuleBridge(engine: jsEngine)
        await bridge.install()
        try checkNotDisposed()
        moduleBridge = bridge

        try await bridge.executeScript(url: productUrl)

        logger.debug("[pocket] worker running: \(productUrl)")
    }

    func dispose() async {
        guard !disposed else { return }
        disposed = true

        let moduleBridge = moduleBridge
        self.moduleBridge = nil
        await moduleBridge?.dispose()

        let engine = engine
        self.engine = nil
        await engine?.destroy()

        executionModel.execution.stopWsBridge()
        executionModel.execution.close()
        executionModel.chainConnections.closeAll()

        logger.debug("[pocket] worker stopped: \(productUrl)")
    }

    private func bootEngine(scripts: [JSEngineScript]) async throws -> JSEngineProtocol {
        let jsEngine = engineFactory()
        do {
            try await jsEngine.initialize(with: scripts)
            guard await jsEngine.getState() == .ready else { throw ScriptExecutorError.engineInitFailed }
            try checkNotDisposed()
        } catch {
            await jsEngine.destroy()
            throw error
        }

        engine = jsEngine
        return jsEngine
    }

    private func checkNotDisposed() throws {
        guard !disposed else { throw CancellationError() }
    }
}
