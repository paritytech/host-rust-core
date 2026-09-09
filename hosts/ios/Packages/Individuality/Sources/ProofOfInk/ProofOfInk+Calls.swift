import Foundation
import SubstrateSdk

public extension ProofOfInkPallet {
    struct ApplyCall: Codable {
        public init() {}

        public func runtimeCall() -> RuntimeCall<NoRuntimeArgs> {
            RuntimeCall(moduleName: ProofOfInkPallet.name, callName: "apply")
        }
    }

    enum InkChoice: Codable {
        private enum InkChoiceType: String, Codable {
            case designedElective = "DesignedElective"
            case proceduralAccount = "ProceduralAccount"
            case proceduralPersonal = "ProceduralPersonal"
            case procedural = "Procedural"
        }

        public struct DesignedElective: Codable {
            enum CodingKeys: String, CodingKey {
                case familyIndex = "0"
                case designIndex = "1"
            }

            @StringCodable public var familyIndex: FamilyIndex
            @StringCodable public var designIndex: DesignIndex
        }

        public struct Procedural: Codable {
            enum CodingKeys: String, CodingKey {
                case familyIndex = "0"
                case variantIndex = "1"
            }

            @StringCodable public var familyIndex: FamilyIndex
            @StringCodable public var variantIndex: VariantIndex
        }

        case designedElective(DesignedElective)
        case proceduralAccount(FamilyIndex)
        case proceduralPersonal(FamilyIndex)
        case procedural(Procedural)

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let type = try container.decode(String.self)
            if let supportedType = InkChoiceType(rawValue: type) {
                switch supportedType {
                case .designedElective:
                    self = try .designedElective(container.decode(DesignedElective.self))
                case .proceduralAccount:
                    self = try .proceduralAccount(container.decode(StringScaleMapper<FamilyIndex>.self).value)
                case .proceduralPersonal:
                    self = try .proceduralPersonal(container.decode(StringScaleMapper<FamilyIndex>.self).value)
                case .procedural:
                    self = try .procedural(container.decode(Procedural.self))
                }
            } else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported"
                ))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .designedElective(model):
                try container.encode(InkChoiceType.designedElective.rawValue)
                try container.encode(model)
            case let .proceduralAccount(familyIndex):
                try container.encode(InkChoiceType.proceduralAccount.rawValue)
                try container.encode(StringScaleMapper(value: familyIndex))
            case let .proceduralPersonal(familyIndex):
                try container.encode(InkChoiceType.proceduralPersonal.rawValue)
                try container.encode(StringScaleMapper(value: familyIndex))
            case let .procedural(model):
                try container.encode(InkChoiceType.procedural.rawValue)
                try container.encode(model)
            }
        }
    }

    struct CommitCall: Codable {
        enum CodingKeys: String, CodingKey {
            case choice
            case requireId = "require_id"
        }

        let choice: InkChoice
        @OptionStringCodable var requireId: PersonalId?

        public init(choice: InkChoice, requireId: PersonalId?) {
            self.choice = choice
            self.requireId = requireId
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: ProofOfInkPallet.name,
                callName: "commit",
                args: self
            )
        }
    }

    struct SubmitEvidenceCall: Codable {
        @BytesCodable var evidence: Data

        public init(evidence: Data) {
            self.evidence = evidence
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: ProofOfInkPallet.name,
                callName: "submit_evidence",
                args: self
            )
        }
    }

    struct AllocateFull: Codable {
        public init() {}

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: ProofOfInkPallet.name,
                callName: "allocate_full",
                args: self
            )
        }
    }

    struct RegisterNonReferredPersonCall: Codable {
        @BytesCodable public var key: Data
        @BytesCodable public var destination: AccountId
        @BytesCodable public var proofOfOwnership: Data

        enum CodingKeys: String, CodingKey {
            case key
            case destination
            case proofOfOwnership = "proof_of_ownership"
        }

        public init(key: Data, destination: AccountId, proofOfOwnership: Data) {
            self.key = key
            self.destination = destination
            self.proofOfOwnership = proofOfOwnership
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: ProofOfInkPallet.name,
                callName: "register_non_referred",
                args: self
            )
        }
    }

    struct RegisterReferredPersonCall: Codable {
        @BytesCodable public var key: Data
        @BytesCodable public var destination: AccountId
        @BytesCodable public var proofOfOwnership: Data

        enum CodingKeys: String, CodingKey {
            case key
            case destination
            case proofOfOwnership = "proof_of_ownership"
        }

        public init(key: Data, destination: AccountId, proofOfOwnership: Data) {
            self.key = key
            self.destination = destination
            self.proofOfOwnership = proofOfOwnership
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: ProofOfInkPallet.name,
                callName: "register_referred",
                args: self
            )
        }
    }

    struct SetReferralTicketCall: Codable {
        @BytesCodable public var ticket: Data

        public init(ticket: Data) {
            self.ticket = ticket
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: name,
                callName: "set_referral_ticket",
                args: self
            )
        }
    }

    struct CancelReferralTicketCall: Codable {
        public init() {}

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: name,
                callName: "cancel_referral_ticket",
                args: self
            )
        }
    }

    struct RegisterReferralVouchers: Codable {
        enum CodingKeys: String, CodingKey {
            case voucherKey = "voucher_key"
        }

        @BytesCodable public var voucherKey: Data

        public init(voucherKey: Data) {
            self.voucherKey = voucherKey
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: name,
                callName: "register_successful_referral_voucher",
                args: self
            )
        }
    }

    struct ApplyWithSignatureCall: Codable {
        @StringCodable var referrer: PersonalId
        let signature: MultiSignature
        @BytesCodable var ticket: Data

        func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: name,
                callName: "apply_with_signature",
                args: self
            )
        }
    }

    struct ApplyWithInvitationCall: Codable {
        let inviter: AccountId
        @BytesCodable var ticket: Data
        let signature: MultiSignature

        public init(inviter: AccountId, ticket: Data, signature: MultiSignature) {
            self.inviter = inviter
            self.ticket = ticket
            self.signature = signature
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: name,
                callName: "apply_with_invitation",
                args: self
            )
        }
    }

    struct FlakeOutCall: Codable {
        public init() {}

        public func runtimeCall() -> RuntimeCall<NoRuntimeArgs> {
            RuntimeCall(
                moduleName: name,
                callName: "flakeout"
            )
        }
    }
}
