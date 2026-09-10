import Foundation
import WebRTC
import SubstrateSdk
import BigInt

extension Game {
    struct IceCandidate: Codable {
        let sdpMid: String
        let sdpMLineIndex: BigUInt
        let sdp: String
    }
}

extension Game.IceCandidate {
    private enum WrapperError: Error {
        case negativeLineIndex
    }

    init(_ iceCandidate: RTCIceCandidate) throws {
        guard iceCandidate.sdpMLineIndex >= 0 else {
            throw WrapperError.negativeLineIndex
        }

        sdp = iceCandidate.sdp
        sdpMLineIndex = BigUInt(iceCandidate.sdpMLineIndex)
        sdpMid = iceCandidate.sdpMid ?? ""
    }

    var rtcIceCandidate: RTCIceCandidate {
        RTCIceCandidate(
            sdp: sdp,
            sdpMLineIndex: Int32(sdpMLineIndex),
            sdpMid: sdpMid
        )
    }
}

extension Game.IceCandidate: ScaleCodable {
    init(scaleDecoder: any ScaleDecoding) throws {
        sdpMid = try String(scaleDecoder: scaleDecoder)
        sdpMLineIndex = try BigUInt(scaleDecoder: scaleDecoder)
        sdp = try String(scaleDecoder: scaleDecoder)
    }

    func encode(scaleEncoder: any ScaleEncoding) throws {
        try sdpMid.encode(scaleEncoder: scaleEncoder)
        try sdpMLineIndex.encode(scaleEncoder: scaleEncoder)
        try sdp.encode(scaleEncoder: scaleEncoder)
    }
}
