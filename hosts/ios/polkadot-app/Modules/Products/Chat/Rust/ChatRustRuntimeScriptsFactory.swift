import Foundation
import Products
import TrUAPIHost

/// Scripts for the rust chat runtime: bootstrap publishes the ws-bridge
/// endpoint, then the truapi container gates the page.
/// Bootstrap-before-container ordering is load-bearing.
final class ChatRustRuntimeScriptsFactory: ChatScriptsMaking {
    private let bootstrapScript: String

    init(bootstrapScript: String) {
        self.bootstrapScript = bootstrapScript
    }

    func makeScripts() throws -> [String] {
        try [bootstrapScript, ContainerScriptBundle.load()]
    }
}
