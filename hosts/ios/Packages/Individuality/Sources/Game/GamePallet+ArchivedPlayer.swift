import SubstrateSdk

public extension GamePallet {
    enum ArchivedPlayer: Decodable, Equatable {
        case kickable(Kickable)
        case unkickable(Unkickable)

        public struct Kickable: Decodable, Equatable {
            @StringCodable var firstGame: GamePallet.GameIndex
        }

        public struct Unkickable: Decodable, Equatable {
            @StringCodable var firstGame: GamePallet.GameIndex
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let state = try container.decode(String.self)

            switch state {
            case "Kickable":
                let wrapped = try container.decode(Kickable.self)
                self = .kickable(wrapped)
            case "Unkickable":
                let wrapped = try container.decode(Unkickable.self)
                self = .unkickable(wrapped)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported game state: \(state)"
                )
            }
        }

        public var firstGame: GamePallet.GameIndex {
            switch self {
            case let .kickable(kickable):
                kickable.firstGame
            case let .unkickable(unkickable):
                unkickable.firstGame
            }
        }
    }
}
