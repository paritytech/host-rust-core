import Foundation
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

/// One headless worker runtime serves every modality, so a worker script is
/// given the same engine whichever surface asked for it.
struct TrUAPIWorkerRuntimeTests {
    /// The handler is what turns a `getUserMedia` call into the host's own
    /// permission prompt. Without it the engine denies the request outright, so
    /// the same worker script would be prompted under chat and refused here.
    @Test
    func letsTheWorkerAskForTheDeviceCapabilitiesItDeclares() async throws {
        let engine = MockJSEngine()
        let runtime = makeRuntime(engine: engine)

        try await runtime.start()

        #expect(engine.mediaHandlerWasInstalledAtInitialization)

        await runtime.dispose()
    }
}

private func makeRuntime(engine: MockJSEngine) -> TrUAPIWorkerRuntime {
    TrUAPIWorkerRuntime(
        productUrl: URL(string: "https://product.invalid/worker.js")!,
        executionModel: RustRuntimeEnvironment.ExecutionModel(
            execution: MockProductExecution(),
            chainConnections: MockChainConnections(),
            osPermissionAsker: OSPermissionAsker()
        ),
        engineFactory: { engine }
    )
}
