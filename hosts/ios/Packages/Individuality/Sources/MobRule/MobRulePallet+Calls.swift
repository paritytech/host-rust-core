import Foundation
import SubstrateSdk

public extension MobRulePallet {
    struct VoteCall: Codable {
        enum CodingKeys: String, CodingKey {
            case caseIndex = "case_index"
            case opinion
        }

        @StringCodable var caseIndex: CaseIndex
        let opinion: Judgement

        public init(caseIndex: CaseIndex, opinion: Judgement) {
            self.caseIndex = caseIndex
            self.opinion = opinion
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: MobRulePallet.name,
                callName: "vote",
                args: self
            )
        }
    }

    struct PayoutRewardsCall: Codable {
        @BytesCodable var voucher: Data

        public init(voucher: Data) {
            self.voucher = voucher
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: MobRulePallet.name,
                callName: "payout_rewards",
                args: self
            )
        }
    }

    struct ClaimVotesCall: Codable {
        enum CodingKeys: String, CodingKey {
            case caseIndices = "case_indices"
        }

        public let caseIndices: [String]

        public init(caseIndices: [String]) {
            self.caseIndices = caseIndices
        }

        public func runtimeCall() -> RuntimeCall<Self> {
            RuntimeCall(
                moduleName: MobRulePallet.name,
                callName: "claim_votes",
                args: self
            )
        }
    }

    enum ClaimCreditCall {
        public static func runtimeCall() -> RuntimeCall<NoRuntimeArgs> {
            RuntimeCall(
                moduleName: MobRulePallet.name,
                callName: "claim_credit"
            )
        }
    }
}
