import Foundation
import SubstrateSdk

public struct Sr25519VrfSignature: Codable {
    enum CodingKeys: String, CodingKey {
        case preOutput
        case proof
    }

    @BytesCodable public var preOutput: Data
    @BytesCodable public var proof: Data

    public init(preOutput: Data, proof: Data) {
        self.preOutput = preOutput
        self.proof = proof
    }
}

public extension GamePallet {
    enum AirdropVrfs: Codable {
        case account([Sr25519VrfSignature])
        case alias(AliasFields)

        public struct AliasFields: Codable {
            enum CodingKeys: String, CodingKey {
                case proofs
                case ringIndex
                case revision
            }

            let proofs: [BytesCodable]
            @StringCodable public var ringIndex: MembersPallet.RingIndex
            @StringCodable public var revision: MembersPallet.RevisionIndex

            public init(
                proofs: [Data],
                ringIndex: MembersPallet.RingIndex,
                revision: MembersPallet.RevisionIndex
            ) {
                self.proofs = proofs.map { BytesCodable(wrappedValue: $0) }
                _ringIndex = StringCodable(wrappedValue: ringIndex)
                _revision = StringCodable(wrappedValue: revision)
            }
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let variant = try container.decode(String.self)

            switch variant {
            case "Account":
                let signatures = try container.decode([Sr25519VrfSignature].self)
                self = .account(signatures)
            case "Alias":
                let fields = try container.decode(AliasFields.self)
                self = .alias(fields)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported AirdropVrfs variant: \(variant)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()

            switch self {
            case let .account(signatures):
                try container.encode("Account")
                try container.encode(signatures)
            case let .alias(fields):
                try container.encode("Alias")
                try container.encode(fields)
            }
        }
    }
}
