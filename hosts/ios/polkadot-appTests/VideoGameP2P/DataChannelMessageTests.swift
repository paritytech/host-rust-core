@testable import polkadot_app
import Foundation
import SubstrateSdk
import Testing

enum DataChannelMessageTests {
    struct RoundtripTests {
        @Test("Encodes and decodes message with string data")
        func roundtripStringData() throws {
            let message = DataChannelMessage(
                id: "video_game",
                data: Data("hello".utf8)
            )

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try DataChannelMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Encodes and decodes message with empty data")
        func roundtripEmptyData() throws {
            let message = DataChannelMessage(
                id: "test",
                data: Data()
            )

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try DataChannelMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Encodes and decodes message with binary data")
        func roundtripBinaryData() throws {
            let binaryData = Data([0x00, 0x01, 0xFF, 0xFE, 0x80])
            let message = DataChannelMessage(
                id: "binary_channel",
                data: binaryData
            )

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try DataChannelMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }

        @Test("Preserves use case ID through encoding cycle")
        func preservesUseCaseId() throws {
            let message = DataChannelMessage(
                id: "my_custom_channel",
                data: Data("payload".utf8)
            )

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try DataChannelMessage(scaleDecoder: decoder)

            #expect(decoded.id == "my_custom_channel")
        }

        @Test("Encodes and decodes message with large payload")
        func roundtripLargePayload() throws {
            let largeData = Data(repeating: 0xCD, count: 50_000)
            let message = DataChannelMessage(
                id: "large",
                data: largeData
            )

            let encoded = try message.scaleEncoded()
            let decoder = try ScaleDecoder(data: encoded)
            let decoded = try DataChannelMessage(scaleDecoder: decoder)

            #expect(decoded == message)
        }
    }
}
