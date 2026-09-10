import Foundation
import SubstrateSdk
import Individuality

extension PrivacyVoucherPallet {
    struct ClaimVoucherCall: Codable {
        @BytesCodable var proof: Data
        @BytesCodable var dest: AccountId
        @StringCodable var voucherValue: Balance
        @StringCodable var ringIndex: MembersPallet.RingIndex

        enum CodingKeys: String, CodingKey {
            case proof
            case dest
            case voucherValue = "voucher_value"
            case ringIndex = "ring_index"
        }

        func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: PrivacyVoucherPallet.name,
                callName: "claim_voucher_into_destination",
                args: self
            )
        }
    }
}
