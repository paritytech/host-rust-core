@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

enum VideoGameSignalingEnvelopeTests {
    struct RoundtripTests {
        @Test("Encodes and decodes envelope with reconnected message")
        func roundtripReconnected() throws {
            let envelope = VideoGameSignalingEnvelope(
                gameIndex: 42,
                offerId: "offer-abc",
                message: .reconnected
            )

            let encoded = try envelope.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingEnvelope(scaleDecoder: decoder)

            #expect(decoded == envelope)
        }

        @Test("Encodes and decodes envelope with offer message")
        func roundtripOffer() throws {
            let envelope = VideoGameSignalingEnvelope(
                gameIndex: 100,
                offerId: "offer-xyz-123",
                message: .offer(Data("sdp-data".utf8))
            )

            let encoded = try envelope.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingEnvelope(scaleDecoder: decoder)

            #expect(decoded == envelope)
        }

        @Test("Preserves game index through encoding cycle")
        func preservesGameIndex() throws {
            let envelope = VideoGameSignalingEnvelope(
                gameIndex: UInt32.max,
                offerId: "test",
                message: .reconnected
            )

            let encoded = try envelope.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingEnvelope(scaleDecoder: decoder)

            #expect(decoded.gameIndex == UInt32.max)
        }

        @Test("Preserves offer ID through encoding cycle")
        func preservesOfferId() throws {
            let longOfferId = String(repeating: "a", count: 256)
            let envelope = VideoGameSignalingEnvelope(
                gameIndex: 1,
                offerId: longOfferId,
                message: .reconnected
            )

            let encoded = try envelope.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingEnvelope(scaleDecoder: decoder)

            #expect(decoded.offerId == longOfferId)
        }

        @Test("Encodes and decodes envelope with empty offer ID")
        func roundtripEmptyOfferId() throws {
            let envelope = VideoGameSignalingEnvelope(
                gameIndex: 0,
                offerId: "",
                message: .answer(Data())
            )

            let encoded = try envelope.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingEnvelope(scaleDecoder: decoder)

            #expect(decoded == envelope)
        }
    }
}
