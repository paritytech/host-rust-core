@testable import polkadot_app
import AsyncExtensions
import Foundation
import Individuality
import MessageExchangeKit
import SubstrateSdk
import Testing

enum VideoGamePeerEngineContextTests {
    @Test("Context starts only once")
    static func startIsIdempotent() async {
        let sut = makeContext(componentFactory: NeverPeerComponentFactory())

        let didStart = await sut.start()
        let didStartAgain = await sut.start()

        await sut.dispose()

        #expect(didStart)
        #expect(!didStartAgain)
    }

    @Test("Dispose blocks later starts")
    static func disposeBlocksStart() async {
        let sut = makeContext(componentFactory: NeverPeerComponentFactory())

        let didStart = await sut.start()
        await sut.dispose()
        let didStartAfterDispose = await sut.start()

        #expect(didStart)
        #expect(!didStartAfterDispose)
    }

    @Test("Context starts a connection flow after session creation")
    static func startsConnectionFlow() async throws {
        let componentFactory = RecordingPeerComponentFactory()
        var createdFlows = componentFactory.createdFlows.makeAsyncIterator()
        let sut = makeContext(
            componentFactory: componentFactory
        )

        let didStart = await sut.start()
        let flow = try #require(await createdFlows.next())

        await sut.dispose()

        #expect(didStart)
        #expect(flow.startCount == 1)
    }

    @Test("Dispose cancels current connection flow")
    static func disposeCancelsCurrentFlow() async throws {
        let componentFactory = RecordingPeerComponentFactory()
        var createdFlows = componentFactory.createdFlows.makeAsyncIterator()
        let sut = makeContext(
            componentFactory: componentFactory
        )

        _ = await sut.start()
        let flow = try #require(await createdFlows.next())

        await sut.dispose()

        #expect(flow.cancelCount >= 1)
    }

    @Test("Flow active offer event persists offer ID")
    static func activeOfferEventPersistsOfferId() async throws {
        let componentFactory = RecordingPeerComponentFactory()
        let tracker = MockConnectionAttemptTracker()
        var createdFlows = componentFactory.createdFlows.makeAsyncIterator()
        var persistedOfferIds = tracker.persistedOfferIds.makeAsyncIterator()
        let remoteAccountId = Data(repeating: 1, count: 32)
        let sut = makeContext(
            componentFactory: componentFactory,
            attemptTracker: tracker,
            remoteAccountId: remoteAccountId
        )

        _ = await sut.start()
        let flow = try #require(await createdFlows.next())

        flow.emit(.activeOfferId("offer-123"))

        let persistedOfferId = try #require(await persistedOfferIds.next())
        #expect(persistedOfferId == "offer-123")

        await sut.dispose()
    }

    @Test("Context clears persisted offer ID")
    static func clearsPersistedOfferId() async {
        let tracker = MockConnectionAttemptTracker()
        let remoteAccountId = Data(repeating: 1, count: 32)
        let sut = makeContext(
            componentFactory: NeverPeerComponentFactory(),
            attemptTracker: tracker,
            remoteAccountId: remoteAccountId
        )
        tracker.persistOfferId(
            "offer-1",
            gameIndex: VideoGameP2PTestFactory.gameIndex,
            remoteAccountId: remoteAccountId
        )

        await sut.clearPersistedOfferId()

        #expect(
            tracker.getLastOfferId(
                gameIndex: VideoGameP2PTestFactory.gameIndex,
                remoteAccountId: remoteAccountId
            ) == nil
        )
    }

    @Test("Accepted reconnection cancels current flow and starts a new one")
    static func acceptedReconnectionRestartsFlow() async throws {
        let componentFactory = RecordingPeerComponentFactory()
        var createdFlows = componentFactory.createdFlows.makeAsyncIterator()
        let peerSessionDelegate = VideoGamePeerSessionDelegate(peerLogger: Logger.shared)
        let tracker = MockConnectionAttemptTracker()
        let remoteAccountId = Data(repeating: 1, count: 32)
        let sut = makeContext(
            componentFactory: componentFactory,
            peerSessionDelegate: peerSessionDelegate,
            attemptTracker: tracker,
            remoteAccountId: remoteAccountId
        )
        tracker.persistOfferId(
            "offer-1",
            gameIndex: VideoGameP2PTestFactory.gameIndex,
            remoteAccountId: remoteAccountId
        )

        _ = await sut.start()
        let firstFlow = try #require(await createdFlows.next())

        peerSessionDelegate.peerSession(
            VideoGamePeerEngineContextTestPeerSession(),
            didReceiveMessages: [
                OpaqueMessageWrapper(message: VideoGameSignalingEnvelope(
                    gameIndex: VideoGameP2PTestFactory.gameIndex,
                    offerId: "offer-1",
                    message: .reconnected
                ))
            ],
            respondHandler: { _ in }
        )

        let secondFlow = try #require(await createdFlows.next())

        await sut.dispose()

        #expect(firstFlow.cancelCount >= 1)
        #expect(secondFlow.startCount == 1)
    }

    @Test("Reconnection publishes connecting before new flow emits state")
    static func reconnectionPublishesConnectingBeforeNewFlowState() async throws {
        let componentFactory = RecordingPeerComponentFactory()
        var createdFlows = componentFactory.createdFlows.makeAsyncIterator()
        let peerSessionDelegate = VideoGamePeerSessionDelegate(peerLogger: Logger.shared)
        let tracker = MockConnectionAttemptTracker()
        let remoteAccountId = Data(repeating: 1, count: 32)
        let sut = makeContext(
            componentFactory: componentFactory,
            peerSessionDelegate: peerSessionDelegate,
            attemptTracker: tracker,
            remoteAccountId: remoteAccountId
        )
        tracker.persistOfferId(
            "offer-1",
            gameIndex: VideoGameP2PTestFactory.gameIndex,
            remoteAccountId: remoteAccountId
        )

        var iterator = await sut.stateStream().makeAsyncIterator()
        _ = try await iterator.next()

        _ = await sut.start()
        let firstFlow = try #require(await createdFlows.next())
        _ = try await iterator.next()

        firstFlow.emit(.state(.disconnected))
        _ = try await iterator.next()

        peerSessionDelegate.peerSession(
            VideoGamePeerEngineContextTestPeerSession(),
            didReceiveMessages: [
                OpaqueMessageWrapper(message: VideoGameSignalingEnvelope(
                    gameIndex: VideoGameP2PTestFactory.gameIndex,
                    offerId: "offer-1",
                    message: .reconnected
                ))
            ],
            respondHandler: { _ in }
        )

        let nextState = try await iterator.next()

        await sut.dispose()

        guard case .connecting = nextState else {
            Issue.record("Expected connecting state")
            return
        }
    }

    private static func makeContext(
        componentFactory: VideoGamePeerComponentMaking,
        peerSessionDelegate: any VideoGamePeerSessionDelegating = VideoGamePeerSessionDelegate(
            peerLogger: Logger.shared
        ),
        attemptTracker: ConnectionAttemptTracking = MockConnectionAttemptTracker(),
        remoteAccountId: AccountId = Data(repeating: 1, count: 32)
    ) -> VideoGamePeerEngineContext {
        VideoGamePeerEngineContext(
            componentFactory: componentFactory,
            peerSessionDelegate: peerSessionDelegate,
            attemptTracker: attemptTracker,
            gameIndex: VideoGameP2PTestFactory.gameIndex,
            remoteAccountId: remoteAccountId,
            peerLogger: Logger.shared
        )
    }
}

private struct VideoGamePeerEngineContextTestPeerSession: PeerSessionProtocol {
    typealias Message = OpaqueVideoGameSignalingEnvelope

    let peer = VideoGameP2PTestFactory.makePeer()

    var sessionId: MessageExchange.SessionId {
        fatalError("sessionId is not used by VideoGamePeerSessionDelegate")
    }

    func addMessagesToQueue(_: [OpaqueVideoGameSignalingEnvelope]) {}
}
