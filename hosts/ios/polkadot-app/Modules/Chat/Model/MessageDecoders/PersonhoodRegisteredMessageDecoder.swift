import Foundation
import Foundation_iOS
import SubstrateSdk
import PolkadotUI
import SwiftUI
import Individuality

final class PersonhoodRegisteredMessageDecoder {
    let identifier = MessageDecoderIdentifier.personhoodRegistered
}

extension PersonhoodRegisteredMessageDecoder: ChatMessageCustomDecoding {
    func decode(data: Data, context _: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        do {
            let decoder = try ScaleDecoder(data: data)
            _ = try Content(scaleDecoder: decoder)
            return [ChatSystemMessageConfiguration.personhoodRegistered()]
        } catch {
            return []
        }
    }

    func previewString(data: Data) -> String {
        guard
            let decoder = try? ScaleDecoder(data: data),
            (try? Content(scaleDecoder: decoder)) != nil
        else {
            return ""
        }
        return String(localized: .ChatExtension.personhoodRegisteredPreview)
    }
}

// MARK: - Content

extension PersonhoodRegisteredMessageDecoder {
    struct Content {
        let personalId: PeoplePallet.PersonalId

        var identifier: String {
            [
                "personRegistered",
                "\(personalId)"
            ].joined(with: .colon)
        }
    }
}

extension PersonhoodRegisteredMessageDecoder.Content: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        personalId = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try personalId.encode(scaleEncoder: scaleEncoder)
    }
}
