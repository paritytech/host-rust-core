import AsyncExtensions
import Foundation
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

/// Serialized so this suite runs one blocking bridge call at a time, and time-limited
/// because a call that never returns would otherwise hang the whole bundle.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct RustChatExecutionBridgeTests {
    /// Only the dependency factory needs the main actor; the suite must not, because
    /// `awaitBlocking` parks the calling thread on a semaphore.
    private func makeBridge(
        api: any ProductChatMessaging,
        callTimeout: DispatchTimeInterval = .seconds(60)
    ) async -> RustChatExecutionBridge {
        // A generous timeout: the production default is a wall clock, and a loaded
        // test bundle can leave a task queued for seconds before it runs.
        await RustChatExecutionBridge(
            dependencies: MainActor.run { makeChatBridgeDependencies() },
            chatMessaging: api,
            callTimeout: callTimeout
        )
    }

    /// Runs a bridge call on a thread of its own, the way the core does.
    ///
    /// `awaitBlocking` parks its caller on a semaphore and waits for a detached task,
    /// which needs a cooperative pool thread to finish. Parking a pool thread instead
    /// starves that task under parallel test load. A shared queue is no better: if its
    /// threads are all parked the block never starts, and then no timeout applies and
    /// the continuation is never resumed. A dedicated thread always runs.
    private func offPool<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { continuation.resume(with: Result { try body() }) }
            thread.name = "chat-bridge-test-call"
            thread.start()
        }
    }

    @Test func createRoomMapsRegistrationStatus() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)

        api.createRoomStatus = .new
        #expect(try await offPool { try bridge.createRoom(roomId: "r", name: "n", icon: "i") } == .new)

        api.createRoomStatus = .exists
        #expect(try await offPool { try bridge.createRoom(roomId: "r", name: "n", icon: "i") } == .exists)
    }

    /// Empty name and icon mean "unset" to the native api, not empty strings.
    @Test func createRoomNormalisesEmptyFields() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)
        _ = try await offPool { try bridge.createRoom(roomId: "r", name: "", icon: "") }
        _ = try await offPool { try bridge.createRoom(roomId: "r2", name: "kept", icon: "icon") }

        #expect(api.createdRooms.first?.name == nil)
        #expect(api.createdRooms.first?.icon == nil)
        #expect(api.createdRooms.last?.name == "kept")
        #expect(api.createdRooms.last?.icon == "icon")
    }

    @Test func postMessageForwardsTextAndCustomOnly() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)

        let messageId = try await offPool { try bridge.postMessage(roomId: "r", content: .text(text: "hi")) }
        #expect(api.sentMessages.count == 1)
        #expect(api.sentRoomIds == ["r"])
        #expect(messageId == "msg-1")

        _ = try await offPool {
            try bridge.postMessage(
                roomId: "r",
                content: .custom(ChatCustomMessage(messageType: "t", payload: Data([1])))
            )
        }
        #expect(api.sentMessages.count == 2)
        if case let .custom(messageType, data) = api.sentMessages.last {
            #expect(messageType == "t")
            #expect(data == Data([1]))
        } else {
            Issue.record("a custom message must keep its type and payload")
        }

        await #expect(throws: HostRejection.self) {
            try await offPool {
                try bridge.postMessage(
                    roomId: "r",
                    content: .reaction(ChatReaction(messageId: "m", emoji: "x"))
                )
            }
        }
        #expect(api.sentMessages.count == 2)
    }

    /// A failing surface must surface as a rejection, not a silent success.
    @Test func postMessageRejectsWhenTheSurfaceFails() async throws {
        let api = RecordingChatMessaging()
        api.sendMessageError = ProductNativeApiError.messagesNotSupported
        let bridge = await makeBridge(api: api)

        // Naming the api's own error is what separates this from a 2 s timeout.
        await #expect(throws: ProductNativeApiError.self) {
            try await offPool { try bridge.postMessage(roomId: "r", content: .text(text: "hi")) }
        }
    }

    /// A roomless body cannot be named by a `RenderContext`, so nothing could
    /// ever draw it: refuse the post rather than file it under the bot's
    /// default chat.
    @Test func postMessageRejectsAnEmptyRoom() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)

        await #expect(throws: HostRejection.self) {
            try await offPool { try bridge.postMessage(roomId: "", content: .text(text: "hi")) }
        }
        #expect(api.sentMessages.isEmpty)
    }

    @Test func registerBotIsRejected() async throws {
        let api = RecordingChatMessaging()
        let bridge = await makeBridge(api: api)

        await #expect(throws: HostRejection.self) {
            try await offPool { try bridge.registerBot(botId: "b", name: "n", icon: "i") }
        }
    }

    @Test func listRoomsReadsTheCurrentRooms() async throws {
        let api = RecordingChatMessaging()
        api.roomsToReturn = [RoomInfo(roomId: "stored", name: nil, icon: nil, participation: .roomHost)]
        let bridge = await makeBridge(api: api)

        let rooms = try await offPool { try bridge.listRooms() }

        #expect(rooms.map(\.roomId) == ["stored"])
        #expect(rooms.map(\.participatingAs) == [.roomHost])
        #expect(api.subscribeRoomsCallCount == 1)
    }

    @Test func listRoomsReportsNoRoomsWhenTheApiHasNone() async throws {
        let api = RecordingChatMessaging()
        api.roomsToReturn = []
        let bridge = await makeBridge(api: api)

        #expect(try await offPool { try bridge.listRooms() }.isEmpty)
    }

    /// The timeout says the send may still land, so it must not be mistaken for a
    /// clean refusal by whoever reads it.
    @Test func aSurfaceThatNeverAnswersTimesOut() async throws {
        let bridge = await makeBridge(api: StallingChatMessaging(), callTimeout: .milliseconds(50))

        await #expect(throws: HostRejection.self) {
            try await offPool { try bridge.postMessage(roomId: "r", content: .text(text: "hi")) }
        }
    }
}

/// Never answers, so the bridge has to fall through to its timeout.
private struct StallingChatMessaging: ProductChatMessaging {
    func sendMessage(_: ProductBotMessage, roomId _: String?) async throws -> String {
        try await Task.sleep(for: .seconds(60))
        return ""
    }

    func createRoom(_: CreateRoomRequest) async throws -> CreateRoomResult {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }

    func subscribeRooms() async throws -> AnyAsyncSequence<[RoomInfo]> {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
}
