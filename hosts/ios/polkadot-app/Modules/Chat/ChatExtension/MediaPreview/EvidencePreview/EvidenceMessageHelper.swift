import Foundation
import SubstrateSdk

enum EvidenceMessageHelper {
    struct EvidenceData {
        let evidenceId: String
        let type: EvidencePreviewType
    }

    static func extractEvidenceData(from message: Chat.LocalMessage) -> EvidenceData? {
        guard case let .customRendered(content) = message.content else {
            return nil
        }

        let type: EvidencePreviewType
        switch content.decoderId {
        case MessageDecoderIdentifier.evidencePhoto.rawValue:
            type = .photo
        case MessageDecoderIdentifier.evidenceVideo.rawValue:
            type = .video
        default:
            return nil
        }

        guard let payload = try? EvidenceMessageDecoder.Payload(
            scaleDecoder: ScaleDecoder(data: content.data)
        ) else {
            return nil
        }

        return EvidenceData(
            evidenceId: payload.previewId,
            type: type
        )
    }
}
