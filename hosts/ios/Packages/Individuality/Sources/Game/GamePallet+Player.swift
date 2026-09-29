import SubstrateSdk

public extension GamePallet {
    struct Player: Decodable, Equatable {
        public let registered: Bool
        public let sentReport: Bool
        @StringCodable public var firstGame: GamePallet.GameIndex
        public let credibility: PlayerCredibility
    }

    enum PlayerCredibility: Decodable {
        case recognized
        case deposit
        case invited

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let type = try container.decode(String.self)

            switch type {
            case "Recognized":
                self = .recognized
            case "Deposit":
                self = .deposit
            case "Invited":
                self = .invited
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported PlayerCredibility type \(type)"
                )
            }
        }
    }
}
