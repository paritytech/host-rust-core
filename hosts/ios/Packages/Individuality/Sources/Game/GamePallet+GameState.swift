import SubstrateSdk

public extension GamePallet {
    enum GameState: Decodable, Equatable {
        case registration
        case shuffle
        case reporting(playerCount: UInt32)
        case playerProcess
        case cancelling

        private struct PlayerCount: Decodable {
            @StringCodable var playerCount: UInt32
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let state = try container.decode(String.self)

            switch state {
            case "Registration":
                self = .registration
            case "Shuffle":
                self = .shuffle
            case "Reporting":
                let wrapped = try container.decode(PlayerCount.self)
                self = .reporting(playerCount: wrapped.playerCount)
            case "PlayerProcess":
                self = .playerProcess
            case "Cancelling":
                self = .cancelling
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported game state: \(state)"
                )
            }
        }
    }
}
