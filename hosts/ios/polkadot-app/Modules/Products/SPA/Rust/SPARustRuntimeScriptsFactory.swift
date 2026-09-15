import Foundation
import Products
import TrUAPIHost

/// Scripts for the rust runtime: bootstrap publishes the ws-bridge endpoint,
/// then the truapi container gates the page; zoom disable is shared with the
/// native factory. Bootstrap-before-container ordering is load-bearing.
final class SPARustRuntimeScriptsFactory: SPAScriptsMaking {
    private let bootstrapScript: String

    init(bootstrapScript: String) {
        self.bootstrapScript = bootstrapScript
    }

    func makeScripts() throws -> [JSEngineScript] {
        let bootstrap = JSEngineScript(content: bootstrapScript, insertionPoint: .atDocStart)

        let container = try JSEngineScript(
            content: ContainerScriptBundle.load(),
            insertionPoint: .atDocStart,
            frameScope: .allFrames
        )

        return [bootstrap, container, .disableZoom]
    }
}
