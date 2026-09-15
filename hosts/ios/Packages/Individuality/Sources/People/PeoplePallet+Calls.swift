import Foundation
import SubstrateSdk

public extension PeoplePallet {
    struct SetAliasAccountCall: Codable {
        enum CodingKeys: String, CodingKey {
            case account
            case callValidAt = "call_valid_at"
        }

        @BytesCodable public var account: AccountId
        @StringCodable public var callValidAt: BlockNumber

        public init(account: AccountId, callValidAt: BlockNumber) {
            _account = BytesCodable(wrappedValue: account)
            _callValidAt = StringCodable(wrappedValue: callValidAt)
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: PeoplePallet.name,
                callName: "set_alias_account",
                args: self
            )
        }
    }

    struct SetPersonalIdAccount: Codable {
        enum CodingKeys: String, CodingKey {
            case account
            case callValidAt = "call_valid_at"
        }

        @BytesCodable public var account: AccountId
        @StringCodable public var callValidAt: BlockNumber

        public init(account: AccountId, callValidAt: BlockNumber) {
            _account = BytesCodable(wrappedValue: account)
            _callValidAt = StringCodable(wrappedValue: callValidAt)
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: PeoplePallet.name,
                callName: "set_personal_id_account",
                args: self
            )
        }
    }
}
