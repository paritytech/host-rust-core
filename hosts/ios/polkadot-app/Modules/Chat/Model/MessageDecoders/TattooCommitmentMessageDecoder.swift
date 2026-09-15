import Foundation
import PolkadotUI
import SubstrateSdk
import Individuality

struct TattooCommitmentMessageDecoder {}

extension TattooCommitmentMessageDecoder: ChatMessageCustomDecoding {
    var identifier: MessageDecoderIdentifier {
        MessageDecoderIdentifier.tattooCommitted
    }

    func decode(data: Data, context _: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        guard let payload = try? Payload(scaleDecoder: ScaleDecoder(data: data)) else {
            return []
        }

        let provider = TattooChatMessageMediaPreviewProvider(
            design: payload.design,
            familyId: payload.familyId
        )

        let mediaConfiguration = ChatMessageMediaViewConfiguration(
            previewProvider: provider,
            previewBackgroundColor: .white100,
            corners: .tattooMedia
        )

        let nameProvider = TattooChatMessageNameProvider(familyId: payload.familyId)

        let config = TattooCommitmentMessageViewConfiguration(
            mediaConfiguration: mediaConfiguration,
            tattooNameProvider: nameProvider
        )

        return [config]
    }

    func previewString(data: Data) -> String {
        guard (try? Payload(scaleDecoder: ScaleDecoder(data: data))) != nil else {
            return ""
        }

        return String(localized: .Tattoo.messageCommitPreview)
    }
}

// MARK: - Content

extension TattooCommitmentMessageDecoder {
    struct Payload: Equatable, ScaleCodable {
        let familyId: ProofOfInkPallet.FamilyId
        let design: ProofOfInkPallet.InkSpec
        let since: BlockNumber

        init(
            familyId: ProofOfInkPallet.FamilyId,
            design: ProofOfInkPallet.InkSpec,
            since: BlockNumber
        ) {
            self.familyId = familyId
            self.design = design
            self.since = since
        }

        init(scaleDecoder: any ScaleDecoding) throws {
            familyId = try Data(scaleDecoder: scaleDecoder)
            design = try ProofOfInkPallet.InkSpec(scaleDecoder: scaleDecoder)
            since = try BlockNumber(scaleDecoder: scaleDecoder)
        }

        func encode(scaleEncoder: any ScaleEncoding) throws {
            try familyId.encode(scaleEncoder: scaleEncoder)
            try design.encode(scaleEncoder: scaleEncoder)
            try since.encode(scaleEncoder: scaleEncoder)
        }
    }
}
