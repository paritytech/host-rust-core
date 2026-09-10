import Foundation
import SubstrateSdk

public extension GamePallet {
    enum Report: Codable {
        private enum ReportValues: String, Codable {
            case person = "Person"
            case notPerson = "NotPerson"
        }

        case person
        case notPerson

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let value = try container.decode(ReportValues.self)
            switch value {
            case .person:
                self = .person
            case .notPerson:
                self = .notPerson
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            switch self {
            case .person:
                try container.encode(ReportValues.person.rawValue)
            case .notPerson:
                try container.encode(ReportValues.notPerson.rawValue)
            }
            try container.encode(JSON.null)
        }
    }

    typealias FullReport = [[Report]]
}
