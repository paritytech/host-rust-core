@testable import polkadot_app
import Foundation
import MessageExchangeKit
import SubstrateSdk
import Testing

enum VideoGameSignalingSessionTests {
    @Test("Sends ICE candidate batch in one envelope")
    static func sendsIceCandidateBatchInOneEnvelope() async throws {
        let exchangeService = MockVideoGameMessageExchangeService()
        let sut = VideoGameP2PTestFactory.makeSession(exchangeService: exchangeService)
        let candidates = [
            SdpCoderTests.makeIPv4Candidate(foundation: "1", ip: "192.168.1.1", port: 1_001),
            SdpCoderTests.makeIPv4Candidate(foundation: "2", ip: "192.168.1.2", port: 1_002),
            SdpCoderTests.makeIPv4Candidate(foundation: "3", ip: "192.168.1.3", port: 1_003)
        ]

        try await sut.send([.offer(SdpCoderTests.validOfferSdp)])
        let offerId = try #require(exchangeService.queuedMessages.last?.message.offerId)
        try await sut.send([.candidates(candidates)])

        let queuedMessages = exchangeService.queuedMessages
        #expect(queuedMessages.count == 2)

        let envelopes = queuedMessages.dropFirst().map(\.message)
        #expect(envelopes.allSatisfy { $0.gameIndex == VideoGameP2PTestFactory.gameIndex })
        #expect(envelopes.allSatisfy { $0.offerId == offerId })

        let decodedCandidateBatches = try envelopes.map { envelope in
            guard case let .iceCandidates(data) = envelope.message else {
                Issue.record("Expected ICE candidates envelope")
                return [PeerConnectionCandidate]()
            }

            return try SdpCoder().decodeCandidates(data)
        }

        #expect(decodedCandidateBatches.map(\.count) == [3])
        #expect(decodedCandidateBatches.flatMap { $0 } == candidates)
    }

    @Test("Splits a batch at the latest reconnection, dropping earlier envelopes")
    static func splitsBatchAtReconnection() async throws {
        let peer = VideoGameP2PTestFactory.makePeer()
        let staleOffer = try await makeOfferEnvelope(peer: peer)
        let reconnect = VideoGameSignalingEnvelope(
            gameIndex: VideoGameP2PTestFactory.gameIndex,
            offerId: "r1",
            message: .reconnected
        )
        let newOffer = try await makeOfferEnvelope(peer: peer)

        let sut = VideoGameP2PTestFactory.makeSession(peer: peer)
        let reconnection = try #require(
            await sut.reconnection(in: [staleOffer, reconnect, newOffer], isValidOffer: { _ in true })
        )

        #expect(reconnection.offerId == "r1")
        #expect(reconnection.following == [newOffer])
    }

    @Test("Ignores a reconnection for a different game")
    static func ignoresReconnectionForOtherGame() async {
        let peer = VideoGameP2PTestFactory.makePeer()
        let sut = VideoGameP2PTestFactory.makeSession(peer: peer)

        let otherGame = VideoGameSignalingEnvelope(gameIndex: 8, offerId: "offer-1", message: .reconnected)

        #expect(await sut.reconnection(in: [otherGame], isValidOffer: { _ in true }) == nil)
    }

    @Test("Delivers an incoming offer on the signals stream")
    static func deliversIncomingOffer() async throws {
        let peer = VideoGameP2PTestFactory.makePeer()
        let offer = try await makeOfferEnvelope(peer: peer)

        let sut = VideoGameP2PTestFactory.makeSession(peer: peer)
        await sut.handleIncomingEnvelopes([offer])

        #expect(await sut.activeOfferId == offer.offerId)

        var iterator = await (sut.signals).makeAsyncIterator()
        let firstSignal = try await iterator.next()
        #expect(firstSignal == .offer(SdpCoderTests.validOfferSdp))
    }

    /// Produces a valid offer envelope (with a server-assigned offer id) by
    /// sending an offer through a throwaway session.
    private static func makeOfferEnvelope(
        peer: MessageExchange.Peer
    ) async throws -> VideoGameSignalingEnvelope {
        let exchange = MockVideoGameMessageExchangeService()
        let producer = VideoGameP2PTestFactory.makeSession(peer: peer, exchangeService: exchange)

        try await producer.send([.offer(SdpCoderTests.validOfferSdp)])

        return try #require(exchange.queuedMessages.last?.message)
    }

    @Test("Sends signal batch to message exchange at once")
    static func sendsSignalBatchToMessageExchangeAtOnce() async throws {
        let exchangeService = MockVideoGameMessageExchangeService()
        let sut = VideoGameP2PTestFactory.makeSession(exchangeService: exchangeService)
        let candidates = [
            SdpCoderTests.makeIPv4Candidate(foundation: "1", ip: "192.168.1.1", port: 1_001),
            SdpCoderTests.makeIPv4Candidate(foundation: "2", ip: "192.168.1.2", port: 1_002)
        ]

        try await sut.send([
            .offer(SdpCoderTests.validOfferSdp),
            .candidates(candidates)
        ])

        #expect(exchangeService.queuedMessageBatches.count == 1)

        let envelopes = exchangeService.queuedMessages.map(\.message)
        #expect(envelopes.count == 1)

        guard case let .offer(setupData) = envelopes[0].message else {
            Issue.record("Expected offer envelope")
            return
        }

        let setup = try SdpCoder().decodeSetup(setupData)
        #expect(setup.setupSdp == SdpCoderTests.validOfferSdp)
        #expect(setup.candidates == candidates)
    }
}
