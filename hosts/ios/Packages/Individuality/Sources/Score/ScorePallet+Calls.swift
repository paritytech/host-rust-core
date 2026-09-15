import Foundation
import SubstrateSdk

public extension ScorePallet {
    struct KeyWithProof {
        @BytesCodable public var key: Data
        @BytesCodable public var proofOfOwnership: Data

        public init(key: Data, proofOfOwnership: Data) {
            self.key = key
            self.proofOfOwnership = proofOfOwnership
        }
    }

    struct RegisterCall: Codable {
        @NullCodable public var key: KeyWithProof?

        public init(key: KeyWithProof?) {
            _key = NullCodable(wrappedValue: key)
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: ScorePallet.name,
                callName: "register",
                args: self
            )
        }
    }

    struct RedeemCreditCall: Codable {
        @BytesCodable public var voucher: Data

        public init(voucher: Data) {
            _voucher = BytesCodable(wrappedValue: voucher)
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: ScorePallet.name,
                callName: "redeem_credit",
                args: self
            )
        }
    }
}

extension ScorePallet.KeyWithProof: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        key = try container.decode(BytesCodable.self).wrappedValue
        proofOfOwnership = try container.decode(BytesCodable.self).wrappedValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(key)
        try container.encode(proofOfOwnership)
    }
}
