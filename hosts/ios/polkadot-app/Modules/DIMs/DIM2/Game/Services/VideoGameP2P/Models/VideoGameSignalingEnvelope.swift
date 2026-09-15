import Foundation
import SubstrateSdk
import Individuality

typealias OpaqueVideoGameSignalingEnvelope = OpaqueMessageWrapper<VideoGameSignalingEnvelope>

struct VideoGameSignalingEnvelope: Equatable {
    let gameIndex: GamePallet.GameIndex
    let offerId: String
    let message: VideoGameSignalingMessage
}

extension VideoGameSignalingEnvelope: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        gameIndex = try GamePallet.GameIndex(scaleDecoder: scaleDecoder)
        offerId = try String(scaleDecoder: scaleDecoder)
        message = try VideoGameSignalingMessage(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try gameIndex.encode(scaleEncoder: scaleEncoder)
        try offerId.encode(scaleEncoder: scaleEncoder)
        try message.encode(scaleEncoder: scaleEncoder)
    }
}
