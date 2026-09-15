import Foundation
import SubstrateSdk
import PolkadotUI

final class VideoEvidenceMessageDecoder: EvidenceMessageDecoder {
    override var decoderIdentifier: MessageDecoderIdentifier {
        .evidenceVideo
    }

    override var evidenceType: EvidenceType {
        .video
    }
}

final class PhotoEvidenceMessageDecoder: EvidenceMessageDecoder {
    override var decoderIdentifier: MessageDecoderIdentifier {
        .evidencePhoto
    }

    override var evidenceType: EvidenceType {
        .photo
    }
}

class EvidenceMessageDecoder {
    private let timeFormatter: TimestampFormatting
    private let logger: LoggerProtocol

    var decoderIdentifier: MessageDecoderIdentifier {
        fatalError("Override")
    }

    var evidenceType: EvidenceType {
        fatalError("Override")
    }

    init(
        timeFormatter: TimestampFormatting = MessageShortTimestampFormatter(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.timeFormatter = timeFormatter
        self.logger = logger
    }
}

extension EvidenceMessageDecoder {
    enum EvidenceType {
        case photo
        case video
    }

    var mediaType: EvidenceMediaType {
        switch evidenceType {
        case .photo: .photo
        case .video: .video
        }
    }
}

extension EvidenceMessageDecoder: ChatMessageCustomDecoding {
    var identifier: MessageDecoderIdentifier {
        decoderIdentifier
    }

    func decode(data: Data, context: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        guard let payload = try? Payload(scaleDecoder: ScaleDecoder(data: data)) else {
            return []
        }

        let previewId = payload.previewId

        let previewProvider = EvidenceMessageMediaPreviewProvider(
            type: mediaType,
            fileManager: EvidenceFileManager(fileManager: .default, evidenceId: previewId)
        )

        let mediaConfiguration = ChatMessageMediaViewConfiguration(
            previewProvider: previewProvider,
            corners: .evidenceMedia,
            status: mediaStatus(payload: payload),
            deliveryDetails: deliveryDetails(payload: payload),
            buttonConfiguration: buttonConfiguration(payload: payload, context: context),
            tapOnMedia: { [weak self] in
                self?.handleTapOnMedia(context: context)
            }
        )

        let config = EvidenceMessageViewConfiguration(
            mediaConfiguration: mediaConfiguration,
            messageText: statusMessageText(),
            status: status(payload: payload, context: context),
            additionalMessageText: additionalMessageText(payload: payload)
        )

        return [config]
    }

    func previewString(data: Data) -> String {
        guard (try? Payload(scaleDecoder: ScaleDecoder(data: data))) != nil else {
            return ""
        }
        switch evidenceType {
        case .photo:
            return String(localized: .Tattoo.evidencePreviewPhoto)
        case .video:
            return String(localized: .Tattoo.evidencePreviewVideo)
        }
    }
}

// MARK: - Content

extension EvidenceMessageDecoder {
    struct Payload {
        let previewId: String
        let status: ProofOfInkChatEvidenceItemModel.State
        let timestamp: UInt64
    }
}

extension EvidenceMessageDecoder.Payload {
    func updating(status: ProofOfInkChatEvidenceItemModel.State) -> Self {
        .init(
            previewId: previewId,
            status: status,
            timestamp: timestamp
        )
    }
}

extension EvidenceMessageDecoder.Payload: Equatable, ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        previewId = try String(scaleDecoder: scaleDecoder)
        status = try ProofOfInkChatEvidenceItemModel.State(scaleDecoder: scaleDecoder)
        timestamp = try UInt64(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try previewId.encode(scaleEncoder: scaleEncoder)
        try status.encode(scaleEncoder: scaleEncoder)
        try timestamp.encode(scaleEncoder: scaleEncoder)
    }
}

extension EvidenceMessageDecoder {
    func mediaStatus(payload: Payload) -> ChatMessageOverlayInfoViewConfiguration? {
        switch payload.status {
        case .waitingToUpload,
             .requestingStorage:
            .mediaUploadQueued()
        case let .uploading(progress: progress):
            .mediaUploading(progress: CGFloat(progress) / 100)
        case .uploadingFailed:
            .mediaUploadFailed()
        case .inReview,
             .reviewed:
            nil
        }
    }

    func status(payload: Payload, context: ChatMessageDecodingContext) -> EvidenceMessageViewConfiguration.StatusModel {
        switch payload.status {
        case .waitingToUpload,
             .requestingStorage:
            .queued()
        case .uploading:
            .uploading()
        case .uploadingFailed:
            .uploadFailed { [weak self] in
                self?.handleButtonAction(for: payload, context: context)
            }
        case .inReview:
            .inReview()
        case .reviewed:
            .approved()
        }
    }

    func deliveryDetails(payload: Payload) -> ChatMessageOverlayInfoViewConfiguration? {
        let date = Date.fromChatTimestamp(payload.timestamp)
        let dateString = timeFormatter.string(for: date)
        switch payload.status {
        case .waitingToUpload,
             .requestingStorage,
             .uploading:
            return .mediaDeliveryInProgress(date: dateString)
        case .uploadingFailed,
             .inReview,
             .reviewed:
            return .mediaDeliverySent(date: dateString)
        }
    }

    func buttonConfiguration(payload: Payload, context: ChatMessageDecodingContext) -> ChatMessageMediaViewConfiguration
        .ButtonConfiguration? {
        guard let style = buttonStyle(payload: payload) else {
            return nil
        }
        return .init(style: style) { [weak self] in
            self?.handleButtonAction(for: payload, context: context)
        }
    }

    func buttonStyle(payload: Payload) -> ChatMessageMediaButtonStyle? {
        if case .uploadingFailed = payload.status {
            return .retry
        }

        if case .uploading = payload.status {
            return .loading(cancelable: false)
        }

        switch evidenceType {
        case .photo:
            return nil
        case .video:
            return .play
        }
    }

    func handleButtonAction(for payload: Payload, context: ChatMessageDecodingContext) {
        let actionIdentifier: String
        switch payload.status {
        case .uploadingFailed:
            actionIdentifier = DIM1ChatExtension.ActionButtonId.retryEvidenceUpload
        case .uploading:
            return
        default:
            actionIdentifier = DIM1ChatExtension.ActionButtonId.openEvidencePreview
        }

        let action = Chat.Action.customMessage(
            actionId: actionIdentifier,
            payload: nil,
            messageId: context.messageId
        )
        context.processAction(action)
    }

    func handleTapOnMedia(context: ChatMessageDecodingContext) {
        let action = Chat.Action.customMessage(
            actionId: DIM1ChatExtension.ActionButtonId.openEvidencePreview,
            payload: nil,
            messageId: context.messageId
        )
        context.processAction(action)
    }

    func statusMessageText() -> String {
        switch evidenceType {
        case .photo:
            String(localized: .Tattoo.evidenceMessagePhoto)
        case .video:
            String(localized: .Tattoo.evidenceMessageVideo)
        }
    }

    func additionalMessageText(payload: Payload) -> String? {
        guard evidenceType == .video,
              payload.status == .waitingToUpload else {
            return nil
        }

        return String(localized: .Tattoo.evidenceMessageUploadBeginsAfterPhoto)
    }
}
