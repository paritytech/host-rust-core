import SubstrateSdk

public extension ScorePallet {
    enum Recognition: Decodable, Equatable {
        case externallyRecognized
        case notRecognized
        case suspended(PersonalId)
        case recognized(PersonalId)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "ExternallyRecognized":
                self = .externallyRecognized
            case "NotRecognized":
                self = .notRecognized
            case "Suspended":
                let wrapped = try container.decode(StringCodable<PersonalId>.self)
                self = .suspended(wrapped.wrappedValue)
            case "Recognized":
                let wrapped = try container.decode(StringCodable<PersonalId>.self)
                self = .recognized(wrapped.wrappedValue)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported recognition: \(rawValue)"
                )
            }
        }

        public var isSuspended: Bool {
            switch self {
            case .suspended:
                true
            case .externallyRecognized,
                 .notRecognized,
                 .recognized:
                false
            }
        }

        public var isRecognized: Bool {
            switch self {
            case .recognized,
                 .externallyRecognized:
                true
            case .notRecognized,
                 .suspended:
                false
            }
        }
    }
}
