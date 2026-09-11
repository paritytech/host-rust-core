import Foundation
import Testing
import AsyncExtensions
import Products
import TrUAPIHost
@testable import polkadot_app

// MARK: - Helpers

private func makeConfiguration(contentSource: SPAContentSource) throws -> SPAConfiguration {
    let tldProvider = StubTldProvider()
    let factory = ProductHostFactory(tldProvider: tldProvider)
    let host = try #require(factory.host(rawString: "test.dot"))

    return SPAConfiguration(
        title: nil,
        isRootScreen: false,
        showMoreButton: false,
        page: ProductPage(host: host),
        contentSource: contentSource
    )
}

private struct StubTldProvider: DotNsTldProviding {
    func currentTld() -> String? {
        "dot"
    }

    func resolveTld() async throws -> String {
        "dot"
    }

    func refresh() {}
}

private func makeRuntime(
    execution: MockProductExecution = MockProductExecution(),
    chainConnections: MockChainConnections = MockChainConnections(),
    configuration: SPAConfiguration,
    dotNsResolver: DotNsResolverProtocol = StubDotNsResolver(),
    productResolver: ProductResolving = StubProductResolver()
) -> SPARustRuntime {
    SPARustRuntime(
        executionModel: makeExecutionModel(execution: execution, chainConnections: chainConnections),
        configuration: configuration,
        dotNsResolver: dotNsResolver,
        productResolver: productResolver,
        schemeHandlerProxy: SchemeHandlerProxy(),
        logger: Logger.shared
    )
}

// MARK: - Tests

struct SPARustRuntimeTests {
    @Test func startWithDirectURLStartsBridgeAndInitializesEngine() async throws {
        let directURL = try #require(URL(string: "http://localhost:3000"))
        let configuration = try makeConfiguration(contentSource: .directURL(directURL))
        let execution = MockProductExecution()
        execution.permissionStatus = .authorized
        let engine = MockJSEngine()
        let runtime = makeRuntime(execution: execution, configuration: configuration)

        let url = try await runtime.start(with: engine)

        #expect(url == directURL)
        #expect(execution.startWsBridgeCallCount == 1)
        #expect(execution.permissionRequests == [
            .remote(RemotePermissionRequest(permission: .webRtc))
        ])

        // Bootstrap → container → zoom disable, doc-start ordering intact.
        #expect(engine.initializedScripts.count == 3)
        #expect(engine.initializedScripts[0].content.contains("truapi-native-ready"))
        #expect(engine.initializedScripts[0].content.contains("webRtcAllowed: true"))
        #expect(engine.initializedScripts[1].content.contains("freezeAndDelete"))

        await runtime.dispose()
    }

    @Test func startWithDotNsResolvesContentAndReturnsProductURL() async throws {
        let configuration = try makeConfiguration(contentSource: .dotNs)
        let resolver = StubDotNsResolver()
        let engine = MockJSEngine()
        let runtime = makeRuntime(configuration: configuration, dotNsResolver: resolver)

        let url = try await runtime.start(with: engine)

        #expect(resolver.resolvedNames == ["test.dot"])
        #expect(url.scheme == ProductScriptSchemeHandler.scheme)
        #expect(url.host == "test.dot")
        #expect(url.path == "/\(ProductBundle.indexHTML)")
        #expect(engine.initializedScripts[0].content.contains("webRtcAllowed: false"))

        await runtime.dispose()
    }

    @Test func disposeTearsDownExecutionOnceAndDestroysEngine() async throws {
        let execution = MockProductExecution()
        let chainConnections = MockChainConnections()
        let configuration = try makeConfiguration(
            contentSource: .directURL(#require(URL(string: "http://localhost:3000")))
        )
        let engine = MockJSEngine()
        let runtime = makeRuntime(
            execution: execution,
            chainConnections: chainConnections,
            configuration: configuration
        )

        _ = try await runtime.start(with: engine)
        await runtime.dispose()
        await runtime.dispose()

        #expect(execution.stopWsBridgeCallCount == 1)
        #expect(execution.closeCallCount == 1)
        #expect(chainConnections.closeAllCallCount == 1)
        #expect(engine.destroyCallCount == 1)
    }

    @Test func scriptsFactoryOrdersBootstrapBeforeContainer() throws {
        let factory = SPARustRuntimeScriptsFactory(bootstrapScript: "/*bootstrap*/")

        let scripts = try factory.makeScripts()

        #expect(scripts.count == 3)
        #expect(scripts[0].content == "/*bootstrap*/")
        #expect(scripts[0].insertionPoint == .atDocStart)
        #expect(scripts[0].frameScope == .mainFrameOnly)
        #expect(scripts[1].content.contains("__truapi_localhost"))
        #expect(scripts[1].insertionPoint == .atDocStart)
        #expect(scripts[1].frameScope == .allFrames)
        #expect(scripts[2].content.contains("viewport"))
        #expect(scripts[2].insertionPoint == .atDocEnd)
        #expect(scripts[2].frameScope == .mainFrameOnly)
    }

    @Test func directURLHandlerAllowsSameHostInterceptsOthers() throws {
        let handler = try DirectURLNavigationDecisionHandler(
            baseURL: #require(URL(string: "http://localhost:3000"))
        )

        let sameHostURL = try #require(URL(string: "http://localhost:3000/page"))
        #expect(handler.decide(url: sameHostURL) == .allow)

        let externalURL = try #require(URL(string: "https://example.com"))
        #expect(handler.decide(url: externalURL) == .intercept(externalURL))
    }
}
