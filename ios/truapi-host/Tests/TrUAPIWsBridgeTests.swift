import Foundation
import Testing
import TrUAPIHost

struct TrUAPIWsBridgeTests {
    @Test(.timeLimit(.minutes(1)))
    func testFeatureSupportedRoundTripOverWsBridge() async throws {
        let core = try TrUAPIHostCore(
            bridge: StubHostBridge(),
            runtimeConfig: Self.makeRuntimeConfig()
        )

        let endpoint = try core.startWsBridge(bindPort: 0)
        defer { core.stopWsBridge() }

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
}

private extension TrUAPIWsBridgeTests {
    static func makeRuntimeConfig() -> RuntimeConfig {
        RuntimeConfig(
            productId: "test.dot",
            hostName: "truapi-host-tests",
            peopleChainGenesisHash: Data(repeating: 0, count: 32),
            bulletinChainGenesisHash: Data(repeating: 0, count: 32)
        )
    }

    // wire_table.rs: SYSTEM_FEATURE_SUPPORTED.request_id = 2
    static let featureSupportedRequestDiscriminant = Data([0x02])

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
// Conforms to `ChatHostBridge` so a new requirement there fails this job.
// `registerBot` is left to its default on purpose.
final class StubChatHostBridge: ChatHostBridge {
    func createRoom(
        roomId _: String,
        name _: String,
        icon _: String
    ) throws -> ChatRoomRegistrationStatus { .new }

    func postTextMessage(roomId _: String, text _: String) throws -> String { "message-id" }

    func postCustomMessage(
        roomId _: String,
        messageType _: String,
        payload _: Data
    ) throws -> String { "message-id" }

    func listRooms() throws -> [ChatRoom] { [] }
}

final class StubHostBridge: HostBridge {
    let storage: HostStorageBackend = StubStorage()
    let coreStorage: HostCoreStorageBackend = StubCoreStorage()

    func navigateTo(url _: String) async throws {}
    func devicePermission(request _: HostDevicePermissionRequest) async throws -> Bool { false }
    func remotePermission(request _: RemotePermission) async throws -> Bool { false }
    func featureSupported(request _: HostFeatureSupportedRequest) async throws -> Bool { true }
}
