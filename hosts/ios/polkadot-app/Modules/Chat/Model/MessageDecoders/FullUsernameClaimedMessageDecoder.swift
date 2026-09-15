import Foundation
import Foundation_iOS
import SubstrateSdk
import PolkadotUI
import SwiftUI

final class FullUsernameClaimedMessageDecoder {
    let identifier = MessageDecoderIdentifier.fullUsernameClaimed
}

extension FullUsernameClaimedMessageDecoder: ChatMessageCustomDecoding {
    func decode(data: Data, context _: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        do {
            let decoder = try ScaleDecoder(data: data)
            let content = try Content(scaleDecoder: decoder)
            let config = ChatSystemMessageConfiguration.fullUsernameClaimed(
                liteUsername: content.liteUsername.value,
                fullUsername: content.fullUsername.value
            )
            return [config]
        } catch {
            return []
        }
    }

    func previewString(data: Data) -> String {
        guard
            let decoder = try? ScaleDecoder(data: data),
            let content = try? Content(scaleDecoder: decoder)
        else {
            return ""
        }
        return String(localized: .ChatExtension.fullUsernameClaimed(
            content.liteUsername.value,
            content.fullUsername.value
        ))
    }
}

// MARK: - Content

extension FullUsernameClaimedMessageDecoder {
    struct Content: Equatable {
        let liteUsername: Username
        let fullUsername: Username

        var identifier: String {
            [
                "usernameClaimed",
                "\(fullUsername.value)"
            ].joined(with: .colon)
        }
    }
}

extension FullUsernameClaimedMessageDecoder.Content: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        liteUsername = try Username(value: String(scaleDecoder: scaleDecoder))
        fullUsername = try Username(value: String(scaleDecoder: scaleDecoder))
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try liteUsername.value.encode(scaleEncoder: scaleEncoder)
        try fullUsername.value.encode(scaleEncoder: scaleEncoder)
    }
}
