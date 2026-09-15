import Foundation
import SubstrateSdk

enum VideoGameSignalingMessage: Equatable {
    static let reconnectedIndex: UInt8 = 0
    static let offerIndex: UInt8 = 1
    static let answerIndex: UInt8 = 2
    static let iceCandidatesIndex: UInt8 = 3

    case reconnected
    case offer(Data)
    case answer(Data)
    case iceCandidates(Data)

    var isOffer: Bool {
        if case .offer = self { return true }
        return false
    }

    var isReconnected: Bool {
        if case .reconnected = self { return true }
        return false
    }
}

extension VideoGameSignalingMessage: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        let index = try UInt8(scaleDecoder: scaleDecoder)

        switch index {
        case Self.reconnectedIndex:
            self = .reconnected
        case Self.offerIndex:
            let sdp = try Data(scaleDecoder: scaleDecoder)
            self = .offer(sdp)
        case Self.answerIndex:
            let sdp = try Data(scaleDecoder: scaleDecoder)
            self = .answer(sdp)
        case Self.iceCandidatesIndex:
            let candidates = try Data(scaleDecoder: scaleDecoder)
            self = .iceCandidates(candidates)
        default:
            throw ScaleCodingError.unexpectedDecodedValue
        }
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        switch self {
        case .reconnected:
            try Self.reconnectedIndex.encode(scaleEncoder: scaleEncoder)
        case let .offer(sdp):
            try Self.offerIndex.encode(scaleEncoder: scaleEncoder)
            try sdp.encode(scaleEncoder: scaleEncoder)
        case let .answer(sdp):
            try Self.answerIndex.encode(scaleEncoder: scaleEncoder)
            try sdp.encode(scaleEncoder: scaleEncoder)
        case let .iceCandidates(candidates):
            try Self.iceCandidatesIndex.encode(scaleEncoder: scaleEncoder)
            try candidates.encode(scaleEncoder: scaleEncoder)
        }
    }
}
