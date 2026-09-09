import Foundation
import SubstrateSdk

public extension MobRulePallet {
    typealias FamilyIndex = UInt32
    typealias CaseIndex = UInt32
    typealias SecsSinceGenesis = UInt64
    typealias RoundIndex = UInt32
    typealias VoteCount = UInt64
    typealias Points = UInt32

    typealias VoucherSize = UInt32

    typealias OpenCasesKeyResult = [CasesKey: OpenCase]
    typealias OpenCasesResult = [CaseIndex: OpenCase]
    typealias RipeCasesKeyResult = [CasesKey: RipeCase]
    typealias RipeCasesResult = [CaseIndex: RipeCase]
    typealias DoneCasesKeyResult = [CasesKey: DoneCase]
    typealias DoneCasesResult = [CaseIndex: DoneCase]
    typealias UserVotesResult = Set<CaseIndex>

    struct OpenCase: Codable, Equatable {
        @StringCodable public var since: SecsSinceGenesis
        public let details: CaseDetails
        public let tally: VoteTally
    }

    struct RipeCase: Codable, Equatable {
        public let details: CaseDetails
        public let verdict: Judgement
    }

    struct DoneCase: Codable, Equatable {
        @StringCodable public var since: SecsSinceGenesis
        public let verdict: Judgement
    }

    struct VoteTally: Codable, Equatable {
        @StringCodable public var aye: UInt32
        @StringCodable public var nay: UInt32
        @StringCodable public var contempt: UInt32
    }

    struct CaseDetails: Codable, Equatable {
        @BytesCodable public var context: Data
        public let statement: Statement
    }

    enum Statement: Codable, Equatable {
        private enum StatementType: String, Codable {
            case proofOfInk = "ProofOfInk"
            case identityCredential = "IdentityCredential"
            case usernameValid = "UsernameValid"
        }

        public struct ProofOfInk: Codable, Equatable {
            public let design: ProofOfInkPallet.InkSpec
            @BytesCodable public var evidence: Data
            public let probableAcceptable: Bool
        }

        public struct IdentityCredential: Codable, Equatable {
            public let platform: IdentityPallet.PersonIdentity.Social
            @BytesCodable public var evidence: Data
        }

        public struct UsernameValid: Codable, Equatable {
            @BytesCodable public var username: Data
        }

        case proofOfInk(ProofOfInk)
        case identityCredential(IdentityCredential)
        case usernameValid(UsernameValid)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let type = try container.decode(StatementType.self)
            switch type {
            case .proofOfInk:
                self = try .proofOfInk(container.decode(ProofOfInk.self))
            case .identityCredential:
                self = try .identityCredential(container.decode(IdentityCredential.self))
            case .usernameValid:
                self = try .usernameValid(container.decode(UsernameValid.self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .proofOfInk(value):
                try container.encode(StatementType.proofOfInk.rawValue)
                try container.encode(value)
            case let .identityCredential(value):
                try container.encode(StatementType.identityCredential.rawValue)
                try container.encode(value)
            case let .usernameValid(value):
                try container.encode(StatementType.usernameValid.rawValue)
                try container.encode(value)
            }
        }
    }

    enum Judgement: Codable, Equatable {
        private enum JudgementType: String, Codable {
            case truth = "Truth"
            case contempt = "Contempt"
        }

        public enum Truth: String, Codable {
            private enum TruthValues: String, Codable {
                case confidentTrue = "True"
                case confidentFalse = "False"
            }

            case confidentTrue
            case confidentFalse

            public init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                let value = try container.decode(TruthValues.self)
                switch value {
                case .confidentTrue:
                    self = .confidentTrue
                case .confidentFalse:
                    self = .confidentFalse
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                switch self {
                case .confidentTrue:
                    try container.encode(TruthValues.confidentTrue.rawValue)
                case .confidentFalse:
                    try container.encode(TruthValues.confidentFalse.rawValue)
                }

                try container.encode(JSON.null)
            }
        }

        case truth(Truth)
        case contempt

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let type = try container.decode(JudgementType.self)
            switch type {
            case .truth:
                self = try .truth(container.decode(Truth.self))
            case .contempt:
                self = .contempt
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .truth(value):
                try container.encode(JudgementType.truth.rawValue)
                try container.encode(value)
            case .contempt:
                try container.encode(JudgementType.contempt.rawValue)
                try container.encode(JSON.null)
            }
        }
    }

    struct MobCredit: Decodable, Equatable {
        enum CodingKeys: String, CodingKey {
            case voted
            case correct
            case credit
        }

        @StringCodable public var voted: UInt32
        @StringCodable public var correct: UInt32
        @StringCodable public var credit: Balance

        public var hasVoted: Bool { voted > 0 }

        public static let empty: MobCredit = .init(voted: 0, correct: 0, credit: 0)
    }

    struct CreditDistribution: Decodable, Equatable {
        @StringCodable public var round: RoundIndex
        @StringCodable public var start: BlockNumber
    }

    struct PayoutSchedule: Decodable, Equatable {
        @StringCodable public var period: RoundIndex
    }

    typealias RoundSchedules = [PayoutSchedule]

    struct CasesKey: JSONListConvertible, Hashable {
        public let index: CaseIndex

        public init(index: CaseIndex) {
            self.index = index
        }

        public init(jsonList: [JSON], context: [CodingUserInfoKey: Any]?) throws {
            let expectedElements = 1

            guard jsonList.count == expectedElements else {
                throw JSONListConvertibleError.unexpectedNumberOfItems(
                    expected: expectedElements,
                    actual: jsonList.count
                )
            }

            index = try jsonList[0].map(to: StringScaleMapper<CaseIndex>.self, with: context).value
        }
    }

    struct ExistingVoteKey: Equatable, Hashable, JSONListConvertible {
        public let caseIndex: CaseIndex
        public let alias: PeoplePallet.Alias

        public init(caseIndex: CaseIndex, alias: PeoplePallet.Alias) {
            self.caseIndex = caseIndex
            self.alias = alias
        }

        public init(jsonList: [JSON], context: [CodingUserInfoKey: Any]?) throws {
            guard jsonList.count == 2 else {
                throw JSONListConvertibleError.unexpectedNumberOfItems(
                    expected: 2,
                    actual: jsonList.count
                )
            }

            caseIndex = try jsonList[0].map(
                to: StringScaleMapper.self,
                with: context
            ).value

            alias = try jsonList[1].map(
                to: BytesCodable.self,
                with: context
            ).wrappedValue
        }
    }
}
