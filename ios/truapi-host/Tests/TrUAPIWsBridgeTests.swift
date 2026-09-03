import Foundation
import Testing
import TrUAPIHost

struct TrUAPIWsBridgeTests {
    @Test(.timeLimit(.minutes(1)))
    func testFeatureSupportedRoundTripOverWsBridge() async throws {
        let bridge = StubHostBridge()
        let runtime = try TrUAPIHostRuntime(
            bridge: bridge,
            runtimeConfig: Self.makeHostRuntimeConfig()
        )
        let execution = try runtime.openProductExecution(
            bridge: bridge,
            configuration: ProductExecutionConfig(
                productId: "test.dot",
                executionKind: .app
            )
        )

        let endpoint = try execution.startWsBridge(bindPort: 0)
        defer { execution.stopWsBridge() }

        let url = try #require(URL(string: "ws://127.0.0.1:\(endpoint.port)/?t=\(endpoint.token)"))
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await task.send(.data(Self.featureSupportedRequestFrame()))
        let message = try await task.receive()

        guard case let .data(response) = message else {
            Issue.record("expected binary frame, got \(message)")
            return
        }
        // Frame tail is the SCALE Result payload: Ok(0x00), V1(0x00), supported(0x01).
        #expect(response.suffix(3) == Data([0x00, 0x00, 0x01]))
    }

    /// An iOS host must classify itself as `Ios` without the embedding app
    /// saying so, since the only way to reach this package is from an iOS app.
    @Test(.timeLimit(.minutes(1)))
    func testHostInfoReportsTheIosPlatform() async throws {
        let bridge = StubHostBridge()
        let runtime = try TrUAPIHostRuntime(
            bridge: bridge,
            runtimeConfig: Self.makeHostRuntimeConfig()
        )
        let execution = try runtime.openProductExecution(
            bridge: bridge,
            configuration: ProductExecutionConfig(
                productId: "test.dot",
                executionKind: .app
            )
        )

        let endpoint = try execution.startWsBridge(bindPort: 0)
        defer { execution.stopWsBridge() }

        let url = try #require(URL(string: "ws://127.0.0.1:\(endpoint.port)/?t=\(endpoint.token)"))
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        try await task.send(.data(Self.hostInfoRequestFrame()))
        let message = try await task.receive()

        guard case let .data(response) = message else {
            Issue.record("expected binary frame, got \(message)")
            return
        }
        #expect(response.suffix(Self.hostInfoResponseTail.count) == Self.hostInfoResponseTail)
    }
}

private extension TrUAPIWsBridgeTests {
    static func makeHostRuntimeConfig() -> HostRuntimeConfig {
        HostRuntimeConfig(
            hostName: "truapi-host-tests",
            peopleChainGenesisHash: Data(repeating: 0, count: 32),
            bulletinChainGenesisHash: Data(repeating: 0, count: 32)
        )
    }

    // wire_table.rs: SYSTEM_FEATURE_SUPPORTED.request_id = 2
    static let featureSupportedRequestDiscriminant = Data([0x02])

    // wire_table.rs: SYSTEM_HOST_INFO.request_id = 192
    static let hostInfoRequestDiscriminant = Data([0xC0])

    static func hostInfoRequestFrame() -> Data {
        var frame = Data()
        frame.append(contentsOf: [0x0C]) // compact length 3
        frame.append("p:1".data(using: .utf8)!)
        frame.append(hostInfoRequestDiscriminant) // from wire_table.rs
        frame.append(contentsOf: [0x00]) // V1
        return frame
    }

    // SCALE Result payload: Ok(0x00), V1(0x00), then HostInfo as
    // platform(Ios = 0x02), name, version (empty, hostVersion is unset).
    static var hostInfoResponseTail: Data {
        var tail = Data([0x00, 0x00, 0x02, 0x44]) // 0x44 is compact length 17
        tail.append("truapi-host-tests".data(using: .utf8)!)
        tail.append(contentsOf: [0x00])
        return tail
    }

    static func featureSupportedRequestFrame() -> Data {
        var frame = Data()
        frame.append(contentsOf: [0x0C]) // compact length 3
        frame.append("p:1".data(using: .utf8)!)
        frame.append(featureSupportedRequestDiscriminant) // from wire_table.rs
        frame.append(contentsOf: [0x00, 0x00, 0x80]) // V1, Chain, compact(32)
        frame.append(Data(repeating: 0, count: 32))
        return frame
    }
}

final class StubStorage: HostStorageBackend, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func read(key: String) throws -> Data? { store[key] }
    func write(key: String, value: Data) throws { store[key] = value }
    func clear(key: String) throws { store[key] = nil }
}

final class StubCoreStorage: HostCoreStorageBackend, @unchecked Sendable {
    private var store: [Data: Data] = [:]

    func read(key: Data) throws -> Data? { store[key] }
    func write(key: Data, value: Data) throws { store[key] = value }
    func clear(key: Data) throws { store[key] = nil }
}

// Conforms to HostBridge rather than the generated HostCallbacks, so the
// protocol extension supplies every optional callback and a new one cannot
// leave this file behind. Only the six requirements without a default are
// written out.
final class StubHostBridge: HostBridge {
    let storage: HostStorageBackend = StubStorage()
    let coreStorage: HostCoreStorageBackend = StubCoreStorage()

    func navigateTo(url _: String) async throws {}
    func devicePermission(request _: HostDevicePermissionRequest) async throws -> Bool { false }
    func remotePermission(request _: RemotePermission) async throws -> Bool { false }
    func featureSupported(request _: HostFeatureSupportedRequest) async throws -> Bool { true }
    func supportedChains() throws -> HostChainSet { HostChainSet(network: "", chains: []) }
    func localStorageRead(key: String) throws -> Data? { try storage.read(key: key) }
    
    func localStorageWrite(key: String, value: Data) throws {
        try storage.write(key: key, value: value)
    }
    
    func localStorageClear(key: String) throws { try storage.clear(key: key) }
}

// Conforms to `ChatHostBridge` so a new requirement there fails this job.
// Every member is written out: the protocol supplies no defaults.
final class StubChatHostBridge: ChatHostBridge {
    func createRoom(
        roomId _: String,
        name _: String,
        icon _: String
    ) throws -> ChatRoomRegistrationStatus { .new }

    func registerBot(
        botId _: String,
        name _: String,
        icon _: String
    ) throws -> ChatBotRegistrationStatus { .new }

    func postMessage(roomId _: String, content _: ChatMessageContent) throws -> String {
        "message-id"
    }

    func listRooms() throws -> [ChatRoom] { [] }
}
