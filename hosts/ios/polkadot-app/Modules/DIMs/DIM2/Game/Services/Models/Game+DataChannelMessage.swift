import Foundation
import WebRTC
import SubstrateSdk

extension Game {
    enum DataChannelMessage {
        case gestureAcceptance(GestureAcceptanceMessage)
    }
}

extension Game.DataChannelMessage {
    /// Matches Android spec
    struct GestureAcceptanceMessage: ScaleCodable {
        static let useCaseId = "video_game_gesture_acceptance"

        enum State: UInt8 {
            case accept
            case unnaccept

            var scaleIndex: UInt8 {
                switch self {
                case .accept:
                    0
                case .unnaccept:
                    1
                }
            }
        }

        let roundIndex: Int
        let acceptorAccountId: AccountId
        let state: State

        init(
            roundIndex: Int,
            acceptorAccountId: AccountId,
            state: State
        ) {
            self.roundIndex = roundIndex
            self.acceptorAccountId = acceptorAccountId
            self.state = state
        }

        init(scaleDecoder: any ScaleDecoding) throws {
            let index = try UInt8(scaleDecoder: scaleDecoder)
            guard let state = State(rawValue: index) else {
                throw ScaleCodingError.unexpectedDecodedValue
            }
            roundIndex = try Int(UInt32(scaleDecoder: scaleDecoder))
            acceptorAccountId = try AccountId(scaleDecoder: scaleDecoder)
            self.state = state
        }

        func encode(scaleEncoder: any ScaleEncoding) throws {
            try state.scaleIndex.encode(scaleEncoder: scaleEncoder)
            try UInt32(roundIndex).encode(scaleEncoder: scaleEncoder)
            try acceptorAccountId.encode(scaleEncoder: scaleEncoder)
        }
    }
}
