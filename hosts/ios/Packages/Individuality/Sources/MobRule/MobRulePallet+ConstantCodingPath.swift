import Foundation
import SubstrateSdk

public extension MobRulePallet {
    static var minCaseDurationPath: ConstantCodingPath {
        .init(moduleName: name, constantName: "MinCaseDuration")
    }

    static var maxVotingDurationPath: ConstantCodingPath {
        .init(moduleName: name, constantName: "MaxVotingDuration")
    }

    static var maxVotesClaimable: ConstantCodingPath {
        .init(moduleName: name, constantName: "MaxVotesClaimable")
    }

    static var voucherTypePath: ConstantCodingPath {
        .init(moduleName: name, constantName: "MobRuleVoucherType")
    }
}
