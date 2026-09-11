import Foundation
import SubstrateSdk
import KeyDerivation

public extension MembersPallet {
    struct SelfIncludeCall: Codable {
        enum CodingKeys: String, CodingKey {
            case identifier
            case member
            case callValidAt = "call_valid_at"
        }

        @BytesCodable public var identifier: CollectionIdentifier
        @BytesCodable public var member: BandersnatchPubKey
        @StringCodable public var callValidAt: BlockTime

        public init(
            identifier: CollectionIdentifier,
            member: BandersnatchPubKey,
            callValidAt: BlockTime
        ) {
            _identifier = BytesCodable(wrappedValue: identifier)
            _member = BytesCodable(wrappedValue: member)
            _callValidAt = StringCodable(wrappedValue: callValidAt)
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: MembersPallet.name,
                callName: "self_include",
                args: self
            )
        }
    }
}
