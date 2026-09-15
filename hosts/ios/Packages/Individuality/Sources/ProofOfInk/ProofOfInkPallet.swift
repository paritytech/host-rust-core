import Foundation
import SubstrateSdk

public enum ProofOfInkPallet {
    static let name = "ProofOfInk"

    public typealias PersonalId = UInt64
    public typealias AllocationCount = UInt32

    public struct ReferralTicket: Codable, Equatable {
        @BytesCodable public var ticket: Data

        public init(ticket: Data) {
            self.ticket = ticket
        }
    }

    public struct ConfigRecord: Decodable, Equatable {
        @StringCodable public var rerollTimeout: BlockNumber
        @StringCodable public var fasttrackCount: UInt32
        @StringCodable public var maximum: UInt32
        @StringCodable public var fullAllocLen: UInt64
        @StringCodable public var fullAllocCount: UInt32
        @StringCodable public var initAllocLen: UInt64
        @StringCodable public var initAllocCount: UInt32
        @StringCodable public var timeout: BlockNumber
    }

    public enum Allocation: Decodable {
        case initial
        case initDone
        case full

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let type = try container.decode(String.self)

            switch type {
            case "Initial":
                self = .initial
            case "InitDone":
                self = .initDone
            case "Full":
                self = .full
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type: \(type)")
            }
        }
    }

    public enum InkSpec: Codable, Hashable {
        private enum InkSpecType: String, Codable {
            case designedElective = "DesignedElective"
            case proceduralAccount = "ProceduralAccount"
            case proceduralPersonal = "ProceduralPersonal"
            case procedural = "Procedural"
        }

        public struct DesignedElective: Codable, Hashable {
            enum CodingKeys: String, CodingKey {
                case familyIndex = "0"
                case design = "1"
            }

            @StringCodable public var familyIndex: ProofOfInkPallet.FamilyIndex
            @StringCodable public var design: ProofOfInkPallet.DesignIndex
        }

        public struct ProceduralAccount: Codable, Hashable {
            enum CodingKeys: String, CodingKey {
                case familyIndex = "0"
                case accountId = "1"
            }

            @StringCodable public var familyIndex: FamilyIndex
            @BytesCodable public var accountId: AccountId
        }

        public struct ProceduralPersonal: Codable, Hashable {
            enum CodingKeys: String, CodingKey {
                case familyIndex = "0"
                case personalId = "1"
            }

            @StringCodable public var familyIndex: FamilyIndex
            @StringCodable public var personalId: PersonalId
        }

        public struct Procedural: Codable, Hashable {
            enum CodingKeys: String, CodingKey {
                case familyIndex = "0"
                case proceduralSeed = "1"
            }

            @StringCodable public var familyIndex: FamilyIndex
            @BytesCodable public var proceduralSeed: ProceduralSeed
        }

        case designedElective(DesignedElective)
        case proceduralAccount(ProceduralAccount)
        case proceduralPersonal(ProceduralPersonal)
        case procedural(Procedural)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let type = try container.decode(String.self)
            guard let supportedType = InkSpecType(rawValue: type) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported"
                ))
            }
            switch supportedType {
            case .designedElective:
                self = try .designedElective(container.decode(DesignedElective.self))
            case .proceduralAccount:
                self = try .proceduralAccount(container.decode(ProceduralAccount.self))
            case .proceduralPersonal:
                self = try .proceduralPersonal(container.decode(ProceduralPersonal.self))
            case .procedural:
                self = try .procedural(container.decode(Procedural.self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .designedElective(value):
                try container.encode(InkSpecType.designedElective.rawValue)
                try container.encode(value)
            case let .proceduralAccount(value):
                try container.encode(InkSpecType.proceduralAccount.rawValue)
                try container.encode(value)
            case let .proceduralPersonal(value):
                try container.encode(InkSpecType.proceduralPersonal.rawValue)
                try container.encode(value)
            case let .procedural(value):
                try container.encode(InkSpecType.procedural.rawValue)
                try container.encode(value)
            }
        }

        public var familyIndex: FamilyIndex {
            switch self {
            case let .designedElective(designedElective):
                designedElective.familyIndex
            case let .proceduralAccount(proceduralAccount):
                proceduralAccount.familyIndex
            case let .proceduralPersonal(proceduralPersonal):
                proceduralPersonal.familyIndex
            case let .procedural(procedural):
                procedural.familyIndex
            }
        }
    }

    public enum Candidate: Decodable, Equatable {
        public enum Credibility: Decodable {
            case referred
            case deposit
            case invited

            public init(from decoder: any Decoder) throws {
                var container = try decoder.unkeyedContainer()

                let type = try container.decode(String.self)

                switch type {
                case "Referred":
                    self = .referred
                case "Deposit":
                    self = .deposit
                case "Invited":
                    self = .invited
                default:
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Unsupported Credibility type \(type)"
                    )
                }
            }
        }

        public struct Applied: Decodable, Equatable {
            public let cred: Credibility
            @BytesCodable public var entropy: Data
            @StringCodable public var entropySince: BlockNumber
        }

        public struct Selected: Decodable, Equatable {
            public let cred: Credibility
            @StringCodable public var since: BlockNumber
            public var judging: JSON?
            public let allocation: Allocation
            public let design: InkSpec
        }

        public struct Proven: Decodable, Equatable {
            public let design: InkSpec
            public let wasReferred: Bool
            public let wasInvited: Bool
        }

        case applied(Applied)
        case selected(Selected)
        case proven(Proven)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            let type = try container.decode(String.self)

            switch type {
            case "Applied":
                let value = try container.decode(Applied.self)
                self = .applied(value)
            case "Selected":
                let value = try container.decode(Selected.self)
                self = .selected(value)
            case "Proven":
                let value = try container.decode(Proven.self)
                self = .proven(value)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported candidate state: \(type)"
                )
            }
        }
    }
}
