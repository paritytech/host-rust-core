#if canImport(UIKit) && canImport(WebKit)

import Foundation
import Network
import Testing
import UIKit
import WebKit
@testable import TrUAPIHost

@Suite(.serialized)
@MainActor
struct ProductNetworkAccessTests {
    @Test(.timeLimit(.minutes(1)))
    func retainedClientAndFetchRecoverWithoutLifecycleCallbacks() async throws {
        let product = try await NetworkTestProduct.open(initialScripts: ["""
            const NativeSocket = WebSocket;
            const closeSocket = NativeSocket.prototype.close;
            window.WebSocket = new Proxy(NativeSocket, {
              construct(target, args) {
                const socket = Reflect.construct(target, args);
                window.__testDisconnectHost = () => closeSocket.call(socket);
                return socket;
              }
            });
            """])
        defer { product.close() }
        try product.execution.setPermissionAuthorizationStatus(
            request: .remote(RemotePermissionRequest(permission: .remote(domains: ["127.0.0.1"]))),
            status: .authorized
        )
        let remote = product.server.url(host: "127.0.0.1", path: "/allowed")
        let result = try await withNetworkTestTimeout("retained client recovery") {
            try await product.webView.callAsyncJavaScript("""
                const host = window.__HOST_API_CLIENT__;
                const client = host.client;
                const statuses = [];
                host.subscribeConnectionStatus(status => statuses.push(status));
                (await client.system.handshake())._unsafeUnwrap();
                const results = [];
                let interrupted = 0;
                for (let cycle = 0; cycle < 2; cycle++) {
                  client.theme.subscribe().subscribe({ error() { interrupted++; } });
                  const disconnected = new Promise(resolve => {
                    const unsubscribe = host.subscribeConnectionStatus(status => {
                      if (status === 'disconnected') { unsubscribe(); resolve(); }
                    });
                  });
                  window.__testDisconnectHost();
                  await disconnected;
                  (await client.system.handshake())._unsafeUnwrap();
                  results.push(await (await fetch(url)).text());
                }
                return JSON.stringify({
                  sameClient: host.client === client,
                  interrupted,
                  resets: statuses.filter(status => status === 'disconnected').length,
                  results,
                });
                """, arguments: ["url": remote.absoluteString], in: nil, contentWorld: .page) as? String
        }
        #expect(result == """
            {"sameClient":true,"interrupted":2,"resets":2,"results":["allowed","allowed"]}
            """)
        #expect(product.server.requests(path: "/allowed") == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func fetchUsesRustPermissionsAndPreservesNativeRedirects() async throws {
        let product = try await NetworkTestProduct.open()
        defer { product.close() }
        let remote = product.server.url(host: "127.0.0.1", path: "/allowed")
        #expect(try await fetch(product.webView, remote) == "denied")
        #expect(product.server.requests(path: "/allowed") == 0)

        let permission = PermissionAuthorizationRequest.remote(
            RemotePermissionRequest(permission: .remote(domains: ["127.0.0.1"]))
        )
        try product.execution.setPermissionAuthorizationStatus(request: permission, status: .authorized)
        #expect(try await fetch(product.webView, remote) == "allowed")
        #expect(product.server.requests(path: "/allowed") == 1)

        let redirect = product.server.url(host: "127.0.0.1", path: "/redirect-denied")
        #expect(try await fetch(product.webView, redirect) == "allowed")
        #expect(product.server.requests(path: "/blocked") == 1)

        try product.execution.setPermissionAuthorizationStatus(request: permission, status: .denied)
        #expect(try await fetch(product.webView, remote) == "denied")
        #expect(product.server.requests(path: "/allowed") == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func allowOnceAuthorizesOnlyTheNextFetch() async throws {
        let product = try await NetworkTestProduct.open(
            bridge: StubHostBridge(remoteDecisions: [.allowOnce, .deny])
        )
        defer { product.close() }
        let remote = product.server.url(host: "127.0.0.1", path: "/allowed")
        #expect(try await fetch(product.webView, remote) == "allowed")
        #expect(try await fetch(product.webView, remote) == "denied")
        #expect(product.server.requests(path: "/allowed") == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func allowOnceAuthorizesOneWebRtcConnection() async throws {
        let product = try await NetworkTestProduct.open(
            bridge: StubHostBridge(remoteDecisions: [.allowOnce, .deny])
        )
        defer { product.close() }

        let decisions = try await withNetworkTestTimeout("WebRTC permission") {
            try await product.webView.callAsyncJavaScript("""
                const first = new RTCPeerConnection({ iceServers: [] });
                const second = new RTCPeerConnection({ iceServers: [] });
                try {
                  const offers = [await first.createOffer(), await first.createOffer()];
                  let secondDecision = 'allowed';
                  try { await second.createOffer(); } catch { secondDecision = 'denied'; }
                  return [...offers.map(offer => offer.type), secondDecision];
                } finally {
                  first.close();
                  second.close();
                }
                """, arguments: [:], in: nil, contentWorld: .page) as? [String]
        }

        #expect(decisions == ["offer", "offer", "denied"])
    }

    @Test(.timeLimit(.minutes(1)))
    func allowOnceReachesStubbedMediaCaptureOnlyOnce() async throws {
        let bridge = StubHostBridge(deviceDecisions: [.allowOnce, .allowOnce, .deny])
        let product = try await NetworkTestProduct.open(bridge: bridge, initialScripts: ["""
            try {
              window.__testMediaCalls = [];
              Object.defineProperty(Object.getPrototypeOf(navigator.mediaDevices), 'getUserMedia', {
                configurable: true,
                writable: true,
                value: async function(constraints) {
                  window.__testMediaCalls.push({ audio: !!constraints.audio, video: !!constraints.video });
                  return { getTracks: () => [] };
                }
              });
            } catch (error) {
              try {
                window.webkit.messageHandlers.testDiagnostic.postMessage({
                  stage: 'media-stub-error', errorClass: error?.name ?? ''
                });
              } catch {}
              throw error;
            }
            """])
        defer { product.close() }

        let result = try await withNetworkTestTimeout("media permission") {
            try await product.webView.callAsyncJavaScript("""
                if (typeof navigator.mediaDevices?.getUserMedia !== 'function') {
                  throw new Error('Media capture API is not exposed');
                }
                const decisions = [];
                for (let attempt = 0; attempt < 2; attempt++) {
                  try {
                    await navigator.mediaDevices.getUserMedia({ audio: true, video: true });
                    decisions.push('allowed');
                  } catch (error) {
                    if (!(error instanceof DOMException) || error.name !== 'NotAllowedError') throw error;
                    decisions.push('denied');
                  }
                }
                return JSON.stringify({ decisions, captures: window.__testMediaCalls });
                """, arguments: [:], in: nil, contentWorld: .page) as? String
        }

        #expect(result == """
            {"decisions":["allowed","denied"],"captures":[{"audio":true,"video":true}]}
            """)
        #expect(bridge.requestedDevicePermissions == [.camera, .microphone, .camera])
    }

    @Test(.timeLimit(.minutes(1)))
    func stylesheetsAndFontsKeepTheirNativeLoadingBehavior() async throws {
        let product = try await NetworkTestProduct.open()
        defer { product.close() }
        let stylesheet = product.server.url(host: "127.0.0.1", path: "/style.css")
        let font = product.server.url(host: "127.0.0.1", path: "/font.woff2")
        let loaded = try await withNetworkTestTimeout("stylesheet and font") {
            try await product.webView.callAsyncJavaScript("""
                const stylesheetLoaded = await new Promise(resolve => {
                  const link = document.createElement('link');
                  link.rel = 'stylesheet'; link.href = stylesheet;
                  link.onload = () => resolve(true); link.onerror = () => resolve(false);
                  document.head.appendChild(link);
                });
                try { await new FontFace('test-font', `url(${font})`).load(); } catch {}
                return stylesheetLoaded;
                """, arguments: ["stylesheet": stylesheet.absoluteString, "font": font.absoluteString],
                in: nil, contentWorld: .page) as? Bool
        }
        #expect(loaded == true)
        #expect(product.server.requests(path: "/style.css") == 1)
        #expect(product.server.requests(path: "/font.woff2") == 1)
    }

    private func fetch(_ webView: WKWebView, _ url: URL) async throws -> String {
        try await withNetworkTestTimeout("fetch \(url.absoluteString)") {
            try await webView.callAsyncJavaScript(
                "try { const response = await fetch(url); return await response.text(); } catch { return 'denied'; }",
                arguments: ["url": url.absoluteString], in: nil, contentWorld: .page
            ) as? String ?? "evaluation failed"
        }
    }
}

private struct NetworkTestTimeout: Error, CustomStringConvertible {
    let stage: String
    var description: String { "Timed out waiting for \(stage)" }
}

@MainActor
private func withNetworkTestTimeout<Value: Sendable>(
    _ stage: String, operation: @escaping @MainActor () async throws -> Value
) async throws -> Value {
    let result = AsyncThrowingStream<Value, Error>.makeStream()
    let timeout = Task {
        try await Task.sleep(for: .seconds(15))
        result.continuation.finish(throwing: NetworkTestTimeout(stage: stage))
    }
    let task = Task {
        do {
            result.continuation.yield(try await operation())
            result.continuation.finish()
        } catch {
            result.continuation.finish(throwing: error)
        }
    }
    defer {
        timeout.cancel()
        task.cancel()
    }
    var iterator = result.stream.makeAsyncIterator()
    guard let value = try await iterator.next() else { throw CancellationError() }
    return value
}

@MainActor
private final class NetworkTestWindow {
    private let window: UIWindow

    init(_ webView: WKWebView, server: NetworkTestServer) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "Run WebKit tests in NetworkTestHost")
        window = UIWindow(windowScene: scene)
        server.trace("window-created window=\(ObjectIdentifier(window)) webView=\(ObjectIdentifier(webView))")
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let controller = UIViewController()
        controller.view = webView
        window.rootViewController = controller
        window.makeKeyAndVisible()
        server.trace("window-visible attached=\(webView.window === window)")
        #expect(webView.window === window)
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
    }
}

@MainActor
private struct NetworkTestProduct {
    let server: NetworkTestServer
    let execution: TrUAPIProductExecution
    let webView: WKWebView
    let window: NetworkTestWindow
    let navigationDelegate: ProductPageReady

    static func open(
        bridge: StubHostBridge = StubHostBridge(),
        initialScripts: [String] = [],
        testName: String = #function
    ) async throws -> NetworkTestProduct {
        let server = try await NetworkTestServer.start(testName: testName)
        do {
            server.trace("runtime-create-begin")
            let runtime = try TrUAPIHostRuntime(bridge: bridge, runtimeConfig: HostRuntimeConfig(
                hostName: "network-tests", peopleChainGenesisHash: Data(repeating: 0, count: 32),
                bulletinChainGenesisHash: Data(repeating: 0, count: 32),
                assetHubChainGenesisHash: Data(repeating: 1, count: 32), networkSuffix: "paseo",
                databaseDirectory: temporaryDatabaseDirectory()
            ))
            server.trace("runtime-created execution-create-begin")
            let execution = try runtime.openProductExecution(
                bridge: bridge,
                configuration: ProductExecutionConfig(productId: "network.paseo", executionKind: .app)
            )
            server.trace("execution-created")
            let ready = ProductPageReady(server: server)
            let configuration = WKWebViewConfiguration()
            // Local fixtures must not wait for Safari's Safe Browsing database.
            configuration.preferences.isFraudulentWebsiteWarningEnabled = false
            configuration.userContentController.add(ready, name: "testReady")
            configuration.userContentController.add(ready, name: "testDiagnostic")
            configuration.userContentController.addUserScript(WKUserScript(source: """
                (() => {
                  const report = (stage, error) => {
                    try {
                      window.webkit.messageHandlers.testDiagnostic.postMessage({
                        stage, errorClass: error?.name ?? ''
                      });
                    } catch {}
                  };
                  window.addEventListener('error', event => report('window-error', event.error));
                  window.addEventListener('unhandledrejection', event => report('unhandled-rejection', event.reason));
                  report('document-start');
                })();
                """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            for (index, source) in initialScripts.enumerated() {
                configuration.userContentController.addUserScript(WKUserScript(
                    source: """
                        try { window.webkit.messageHandlers.testDiagnostic.postMessage({ stage: 'initial-script-begin', index: \(index) }); } catch {}
                        \(source)
                        try { window.webkit.messageHandlers.testDiagnostic.postMessage({ stage: 'initial-script-end', index: \(index) }); } catch {}
                        """, injectionTime: .atDocumentStart, forMainFrameOnly: true
                ))
            }
            server.trace("webView-create-begin initialScripts=\(initialScripts.count)")
            let webView = WKWebView(frame: .zero, configuration: configuration)
            server.trace("webView-created webView=\(ObjectIdentifier(webView))")
            webView.navigationDelegate = ready
            server.trace("window-create-begin")
            let window = try NetworkTestWindow(webView, server: server)
            do {
                server.trace("host-scripts-install-begin")
                try TrUAPIHost.installProductScripts(
                    into: webView, endpoint: execution.startWsBridge(bindPort: 0)
                )
                server.trace("host-scripts-installed")
                #expect(webView.navigationDelegate === ready)
                #expect(webView.configuration.websiteDataStore.isPersistent)
                try await ready.load(webView, url: server.url(host: "localhost", path: "/product"))
                return NetworkTestProduct(
                    server: server, execution: execution, webView: webView, window: window, navigationDelegate: ready
                )
            } catch {
                window.close()
                server.trace("open-failed errorClass=\(type(of: error))")
                execution.close()
                throw error
            }
        } catch {
            server.stop()
            throw error
        }
    }

    func close() {
        server.trace("close webView=\(ObjectIdentifier(webView))")
        webView.stopLoading()
        window.close()
        execution.close()
        server.stop()
    }
}

@MainActor
private final class ProductPageReady: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var onReady: (() -> Void)?
    private let server: NetworkTestServer
    private var fixtureURL: URL?
    private var receivedReady = false

    init(server: NetworkTestServer) {
        self.server = server
        super.init()
    }

    private func traceState(_ event: String, _ webView: WKWebView, navigation: WKNavigation? = nil) {
        let url = webView.url.map { $0 == fixtureURL ? $0.absoluteString : "<non-fixture>" } ?? "nil"
        let navigationID = navigation.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        server.trace("\(event) webView=\(ObjectIdentifier(webView)) navigation=\(navigationID) url=\(url) loading=\(webView.isLoading) productRequests=\(server.requests(path: "/product")) receivedReady=\(receivedReady) waiting=\(onReady != nil)")
    }

    func load(_ webView: WKWebView, url: URL) async throws {
        fixtureURL = url
        let ready = AsyncStream<Void>.makeStream()
        onReady = {
            ready.continuation.yield(())
            ready.continuation.finish()
        }
        defer { onReady = nil }
        traceState("load-begin", webView)
        let navigation = webView.load(URLRequest(url: url))
        traceState("load-returned", webView, navigation: navigation)
        do {
            try await withNetworkTestTimeout("page ready \(url.absoluteString)") {
                var iterator = ready.stream.makeAsyncIterator()
                guard await iterator.next() != nil else { throw CancellationError() }
            }
            traceState("page-ready-completed", webView, navigation: navigation)
        } catch {
            traceState(error is NetworkTestTimeout ? "page-ready-timeout" : "page-ready-error", webView, navigation: navigation)
            throw error
        }
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "testDiagnostic" {
            let payload = message.body as? [String: Any]
            let stage = payload?["stage"] as? String ?? ""
            let stages = ["document-start", "initial-script-begin", "initial-script-end", "media-stub-error", "window-error", "unhandled-rejection"]
            let errorClass = payload?["errorClass"] as? String ?? ""
            let errorClasses = ["Error", "TypeError", "ReferenceError", "RangeError", "SyntaxError", "EvalError", "URIError", "DOMException"]
            let index = payload?["index"] as? Int ?? -1
            server.trace("js-message stage=\(stages.contains(stage) ? stage : "unknown") errorClass=\(errorClasses.contains(errorClass) ? errorClass : "unknown") script=\(index) mainFrame=\(message.frameInfo.isMainFrame)")
            return
        }
        receivedReady = true
        server.trace("ready-message mainFrame=\(message.frameInfo.isMainFrame) waiting=\(onReady != nil) productRequests=\(server.requests(path: "/product"))")
        let callback = onReady
        onReady = nil
        callback?()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        traceState("navigation-start", webView, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        traceState("navigation-commit", webView, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        traceState("navigation-finish", webView, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        traceState("navigation-fail-provisional errorClass=\(type(of: error)) errorDomain=\((error as NSError).domain) errorCode=\((error as NSError).code)", webView, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        traceState("navigation-fail errorClass=\(type(of: error)) errorDomain=\((error as NSError).domain) errorCode=\((error as NSError).code)", webView, navigation: navigation)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        traceState("web-content-process-terminated", webView)
    }
}

private final class NetworkTestServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private let traceID = UUID().uuidString
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let testName: String

    private init(listener: NWListener, testName: String) {
        self.listener = listener
        self.testName = testName
    }

    func trace(_ event: String) {
        print("[network-page-ready] time=\(Date().timeIntervalSince1970) elapsed=\(ProcessInfo.processInfo.systemUptime - startedAt) fixture=\(traceID) test=\(testName) \(event)")
    }

    @MainActor
    static func start(testName: String) async throws -> NetworkTestServer {
        let server = NetworkTestServer(listener: try NWListener(using: .tcp, on: .any), testName: testName)
        server.trace("listener-start")
        server.listener.newConnectionHandler = { connection in server.accept(connection) }
        let ready = AsyncThrowingStream<Void, Error>.makeStream()
        server.listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                server.trace("listener-ready")
                ready.continuation.yield(())
                ready.continuation.finish()
            case let .failed(error):
                server.trace("listener-failed errorClass=\(type(of: error))")
                ready.continuation.finish(throwing: error)
            default: break
            }
        }
        server.listener.start(queue: DispatchQueue(label: "network-test-server"))
        do {
            try await withNetworkTestTimeout("loopback listener ready") {
                var iterator = ready.stream.makeAsyncIterator()
                guard try await iterator.next() != nil else { throw CancellationError() }
            }
        } catch {
            server.stop()
            throw error
        }
        server.listener.stateUpdateHandler = nil
        return server
    }

    func stop() {
        trace("listener-stop productRequests=\(requests(path: "/product"))")
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    func url(host: String, path: String) -> URL {
        URL(string: "http://\(host):\(listener.port!.rawValue)\(path)")!
    }

    func requests(path: String) -> Int {
        lock.withLock { counts[path, default: 0] }
    }

    private func accept(_ connection: NWConnection) {
        trace("connection-accepted connection=\(ObjectIdentifier(connection))")
        connection.start(queue: DispatchQueue(label: "network-test-connection"))
        receiveRequest(connection, previous: Data())
    }

    private func receiveRequest(_ connection: NWConnection, previous: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            self.trace("connection-receive connection=\(ObjectIdentifier(connection)) hasData=\(data != nil) complete=\(isComplete) hasError=\(error != nil)")
            guard let data, previous.count + data.count <= 65536 else {
                connection.cancel()
                return
            }
            let buffer = previous + data
            guard buffer.range(of: Data("\r\n\r\n".utf8)) != nil else {
                self.receiveRequest(connection, previous: buffer)
                return
            }
            guard let request = String(data: buffer, encoding: .utf8),
                  let path = request.split(separator: " ").dropFirst().first else {
                connection.cancel()
                return
            }
            let count = self.lock.withLock {
                self.counts[String(path), default: 0] += 1
                return self.counts[String(path), default: 0]
            }
            if path == "/product" {
                self.trace("product-request connection=\(ObjectIdentifier(connection)) request=\(count)")
            }
            var status = "200 OK"
            var headers = "Access-Control-Allow-Origin: *\r\nContent-Type: text/html\r\nCache-Control: no-store\r\n"
            var body = "allowed"
            if path == "/product" {
                body = "<script>window.webkit.messageHandlers.testReady.postMessage('ready')</script>"
            } else if path == "/style.css" {
                headers = "Access-Control-Allow-Origin: *\r\nContent-Type: text/css\r\nCache-Control: no-store\r\n"
                body = "body { color: green; }"
            } else if path == "/redirect-denied" {
                status = "302 Found"
                let destination = self.url(host: "[::1]", path: "/blocked")
                headers += "Location: \(destination.absoluteString)\r\n"
                body = ""
            }
            let response = "HTTP/1.1 \(status)\r\n\(headers)Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            let isProduct = path == "/product"
            if isProduct {
                self.trace("product-response-send connection=\(ObjectIdentifier(connection)) request=\(count) status=200")
            }
            connection.send(content: Data(response.utf8), completion: .contentProcessed { error in
                if isProduct {
                    self.trace("product-response-processed connection=\(ObjectIdentifier(connection)) request=\(count) hasError=\(error != nil)")
                }
                connection.cancel()
            })
        }
    }
}

#endif
