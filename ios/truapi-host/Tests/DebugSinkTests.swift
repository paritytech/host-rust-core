import Foundation
import Network
import Testing
import TrUAPIHost

struct DebugSinkTests {
    /// A sink installed from Swift sees both directions of a bridged request,
    /// as a loopback debugger receives them.
    @Test(.timeLimit(.minutes(1)))
    func testInstalledSinkForwardsBridgedFramesToTheDebugger() async throws {
        let debugger = try LoopbackDebugger()
        let debuggerPort = try await debugger.start()
        defer { debugger.stop() }

        let bridge = StubHostBridge()
        let runtime = try TrUAPIHostRuntime(
            bridge: bridge,
            runtimeConfig: HostRuntimeConfig(
                hostName: "truapi-host-tests",
                peopleChainGenesisHash: Data(repeating: 0, count: 32),
                bulletinChainGenesisHash: Data(repeating: 0, count: 32),
                assetHubChainGenesisHash: Data(repeating: 1, count: 32),
                networkSuffix: "paseo"
            )
        )
        let execution = try runtime.openProductExecution(
            bridge: bridge,
            configuration: ProductExecutionConfig(productId: "test.dot", executionKind: .app)
        )
        execution.setDebugSink(try NativeDebugSink.connect(url: "ws://127.0.0.1:\(debuggerPort)"))

        let endpoint = try execution.startWsBridge(bindPort: 0)
        defer { execution.stopWsBridge() }

        let url = try #require(URL(string: "ws://127.0.0.1:\(endpoint.port)/?t=\(endpoint.token)"))
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let request = Self.featureSupportedRequestFrame()
        try await task.send(.data(request))
        guard case let .data(response) = try await task.receive() else {
            Issue.record("expected a binary response frame")
            return
        }

        let envelopes = try await debugger.envelopes(count: 2, within: .seconds(10))
        try #require(envelopes.count == 2, "installed sink never reached the debugger")
        let channelId = try #require(envelopes[0]["channelId"] as? String)
        #expect(channelId.hasPrefix("test.dot#"))
        #expect(envelopes[0]["dir"] as? String == "out")
        #expect(envelopes[0]["frame"] as? String == request.base64EncodedString())
        #expect(envelopes[1]["channelId"] as? String == channelId)
        #expect(envelopes[1]["dir"] as? String == "in")
        #expect(envelopes[1]["frame"] as? String == response.base64EncodedString())
    }

    @Test
    func testSinkRefusesARoutableTarget() {
        #expect(throws: NativeDebugSinkError.self) {
            try NativeDebugSink.connect(url: "ws://192.0.2.1:9231")
        }
    }
}

private extension DebugSinkTests {
    // wire_table.rs: SYSTEM_FEATURE_SUPPORTED { trait_id: 1, method_id: 1 }.
    static func featureSupportedRequestFrame() -> Data {
        var frame = Data()
        frame.append(contentsOf: [0x0C]) // compact length 3
        frame.append("p:1".data(using: .utf8)!)
        frame.append(contentsOf: [0x01, 0x01])
        // message_type=Request(0x00), then the payload: V1(0x00), Chain(0x00),
        // compact(32) (0x80).
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x80])
        frame.append(Data(repeating: 0, count: 32))
        return frame
    }
}

/// Stands in for `@parity/truapi-debugger`'s WebSocket server on loopback and
/// records every text message it receives, parsed as JSON.
private final class LoopbackDebugger: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "truapi.tests.debugger")
    private let lock = NSLock()
    private var received: [[String: Any]] = []
    private var connections: [NWConnection] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(
            NWProtocolWebSocket.Options(),
            at: 0
        )
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            lock.withLock { self.connections.append(connection) }
            connection.start(queue: queue)
            receive(on: connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { [listener] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.withLock { connections.forEach { $0.cancel() } }
    }

    /// Waits until `count` messages have arrived or `timeout` passes, and
    /// returns what arrived either way.
    func envelopes(count: Int, within timeout: Duration) async throws -> [[String: Any]] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let snapshot = lock.withLock { received }
            if snapshot.count >= count { return snapshot }
            try await Task.sleep(for: .milliseconds(20))
        }
        return lock.withLock { received }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            if metadata?.opcode == .text, let data,
               let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                lock.withLock { self.received.append(envelope) }
            }
            if error == nil {
                receive(on: connection)
            }
        }
    }
}
