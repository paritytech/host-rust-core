@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

enum VideoGameSignalingMessageTests {
    struct RoundtripTests {
        @Test("Encodes and decodes reconnected message")
        func roundtripReconnected() throws {
            let message = VideoGameSignalingMessage.reconnected

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Encodes and decodes offer message")
        func roundtripOffer() throws {
            let sdpData = Data("test-offer-sdp".utf8)
            let message = VideoGameSignalingMessage.offer(sdpData)

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Encodes and decodes answer message")
        func roundtripAnswer() throws {
            let sdpData = Data("test-answer-sdp".utf8)
            let message = VideoGameSignalingMessage.answer(sdpData)

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Encodes and decodes iceCandidates message")
        func roundtripIceCandidates() throws {
            let candidatesData = Data("test-ice-candidates".utf8)
            let message = VideoGameSignalingMessage.iceCandidates(candidatesData)

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Encodes and decodes message with empty data")
        func roundtripEmptyData() throws {
            let message = VideoGameSignalingMessage.offer(Data())

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Encodes and decodes message with large payload")
        func roundtripLargePayload() throws {
            let largeData = Data(repeating: 0xAB, count: 10_000)
            let message = VideoGameSignalingMessage.iceCandidates(largeData)

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try VideoGameSignalingMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }
    }

    struct IndexTests {
        @Test("Reconnected uses index 0")
        func reconnectedIndex() throws {
            let encoded = try VideoGameSignalingMessage.reconnected.scaleEncoded()
            #expect(encoded.first == 0)
        }

        @Test("Offer uses index 1")
        func offerIndex() throws {
            let encoded = try VideoGameSignalingMessage.offer(Data()).scaleEncoded()
            #expect(encoded.first == 1)
        }

        @Test("Answer uses index 2")
        func answerIndex() throws {
            let encoded = try VideoGameSignalingMessage.answer(Data()).scaleEncoded()
            #expect(encoded.first == 2)
        }

        @Test("IceCandidates uses index 3")
        func iceCandidatesIndex() throws {
            let encoded = try VideoGameSignalingMessage.iceCandidates(Data()).scaleEncoded()
            #expect(encoded.first == 3)
        }

        @Test("Throws on invalid variant index")
        func throwsOnInvalidIndex() throws {
            let invalidData = Data([255])
            let decoder = try ScaleDecoder(data: invalidData)

            #expect(throws: ScaleCodingError.self) {
                _ = try VideoGameSignalingMessage(scaleDecoder: decoder)
            }
        }
    }
}
