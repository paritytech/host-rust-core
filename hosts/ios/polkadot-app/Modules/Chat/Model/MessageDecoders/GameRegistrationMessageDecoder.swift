import Foundation
import PolkadotUI
import SubstrateSdk

final class GameRegistrationMessageDecoder {
    let identifier = MessageDecoderIdentifier.gameRegistration
}

extension GameRegistrationMessageDecoder: ChatMessageCustomDecoding {
    func decode(data _: Data, context _: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        []
    }

    func previewString(data: Data) -> String {
        guard
            let decoder = try? ScaleDecoder(data: data),
            let content = try? Content(scaleDecoder: decoder)
        else {
            return ""
        }

        let formattedDate = Self.previewDateFormatter.string(from: content.gameDate)
        return String(localized: .Game.chatPreviewGameRegistered(time: formattedDate))
    }

    private static let previewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Content

extension GameRegistrationMessageDecoder {
    struct Content: ScaleCodable {
        let gameIndex: UInt32
        let gameDate: Date

        var identifier: String {
            [
                "game-registration",
                "\(gameIndex)"
            ]
            .joined(with: .dash)
        }

        init(gameIndex: UInt32, gameDate: Date) {
            self.gameIndex = gameIndex
            self.gameDate = gameDate
        }

        init(scaleDecoder: any ScaleDecoding) throws {
            gameIndex = try UInt32(scaleDecoder: scaleDecoder)
            let dateString = try String(scaleDecoder: scaleDecoder)
            guard let date = ISO8601DateFormatter().date(from: dateString) else {
                throw ScaleDecoderError.outOfBounds
            }
            gameDate = date
        }

        func encode(scaleEncoder: any ScaleEncoding) throws {
            try gameIndex.encode(scaleEncoder: scaleEncoder)
            try gameDate.ISO8601Format().encode(scaleEncoder: scaleEncoder)
        }
    }
}
