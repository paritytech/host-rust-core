import SubstrateSdk

public extension ScorePallet {
    enum Streak: Decodable, Equatable {
        case attended(UInt32)
        case absent(UInt32)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "Attended":
                let wrapped = try container.decode(StringCodable<UInt32>.self)
                self = .attended(wrapped.wrappedValue)
            case "Absent":
                let wrapped = try container.decode(StringCodable<UInt32>.self)
                self = .absent(wrapped.wrappedValue)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported streak: \(rawValue)"
                )
            }
        }
    }
}

public extension ScorePallet.Streak {
    func makeIntegerStreak() -> Int {
        switch self {
        case let .attended(value):
            Int(value)
        case let .absent(value):
            -Int(value)
        }
    }
}
