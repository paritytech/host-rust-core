import Foundation
import SubstrateSdk

public extension MobRulePallet {
    static var openCasesPath: StorageCodingPath {
        .init(moduleName: name, itemName: "OpenCases")
    }

    static var ripeCasesPath: StorageCodingPath {
        .init(moduleName: name, itemName: "RipeCases")
    }

    static var doneCasesPath: StorageCodingPath {
        .init(moduleName: name, itemName: "DoneCases")
    }

    static var votesPath: StorageCodingPath {
        .init(moduleName: name, itemName: "Votes")
    }

    static var votingPoints: StorageCodingPath {
        .init(moduleName: name, itemName: "VotingPoints")
    }

    static var caseCountPath: StorageCodingPath {
        .init(moduleName: name, itemName: "CaseCount")
    }

    static var creditsPath: StorageCodingPath {
        .init(moduleName: name, itemName: "Credits")
    }

    static var payoutDistributionPath: StorageCodingPath {
        .init(moduleName: name, itemName: "PayoutDistribution")
    }

    static var roundSchedulesPath: StorageCodingPath {
        .init(moduleName: name, itemName: "RoundSchedules")
    }
}
