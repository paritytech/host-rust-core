import Foundation
import SubstrateSdk

struct ProofOfInkChatEvidenceModel {
    let photoItem: ProofOfInkChatEvidenceItemModel
    let videoItem: ProofOfInkChatEvidenceItemModel
}

struct ProofOfInkChatEvidenceItemModel: Equatable {
    enum State {
        case waitingToUpload
        case requestingStorage
        // progress in range 0...100
        case uploading(progress: UInt8)
        case uploadingFailed
        case inReview
        case reviewed
    }

    let state: State
}

extension ProofOfInkChatEvidenceItemModel: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        state = try State(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try state.encode(scaleEncoder: scaleEncoder)
    }
}

extension ProofOfInkChatEvidenceItemModel.State: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let value = try UInt8(scaleDecoder: scaleDecoder)
        switch value {
        case 0:
            self = .waitingToUpload
        case 1:
            self = .requestingStorage
        case 2:
            let progress = try UInt8(scaleDecoder: scaleDecoder)
            self = .uploading(progress: progress)
        case 3:
            self = .uploadingFailed
        case 4:
            self = .inReview
        case 5:
            self = .reviewed
        default:
            throw ScaleDecoderError.outOfBounds
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case .waitingToUpload:
            try UInt8(0).encode(scaleEncoder: scaleEncoder)
        case .requestingStorage:
            try UInt8(1).encode(scaleEncoder: scaleEncoder)
        case let .uploading(progress):
            try UInt8(2).encode(scaleEncoder: scaleEncoder)
            try progress.encode(scaleEncoder: scaleEncoder)
        case .uploadingFailed:
            try UInt8(3).encode(scaleEncoder: scaleEncoder)
        case .inReview:
            try UInt8(4).encode(scaleEncoder: scaleEncoder)
        case .reviewed:
            try UInt8(5).encode(scaleEncoder: scaleEncoder)
        }
    }
}

extension ProofOfInkChatEvidenceItemModel.State: Equatable {}
