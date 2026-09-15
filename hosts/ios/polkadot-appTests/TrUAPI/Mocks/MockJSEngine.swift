import Foundation
import Products

final class MockJSEngine: JSEngineProtocol, @unchecked Sendable {
    var evaluatedScripts: [String] = []
    private(set) var initializedScripts: [JSEngineScript] = []
    private(set) var destroyCallCount = 0
    private var handlers: [String: JSNativeHandler] = [:]

    func getState() async -> JSEngineState { .ready }

    func initialize(with scripts: [JSEngineScript]) async throws {
        initializedScripts = scripts
    }

    func evaluate(_ script: String) async throws -> Any? {
        evaluatedScripts.append(script)

        // JSESModuleBridge awaits __module_complete__ for the injected module
        // tag; resolve it inline so executeScript does not hang.
        if let range = script.range(of: "__module_complete__.postMessage('") {
            let rest = script[range.upperBound...]
            if let end = rest.firstIndex(of: "'"), let handler = handlers["__module_complete__"] {
                try await handler(String(rest[..<end]))
            }
        }

        return nil
    }

    func registerFunction(name: String, handler: @escaping JSNativeHandler) async {
        handlers[name] = handler
    }

    func dispatchEvent(actionId _: String, payload _: String) async throws {}

    func destroy() async {
        destroyCallCount += 1
    }

    func registerJSDeviceCapabilityHandler(_: @escaping JSDeviceCapabilityHandler) async {}
}
