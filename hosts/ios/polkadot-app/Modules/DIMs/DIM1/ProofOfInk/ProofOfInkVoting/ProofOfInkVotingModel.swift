import Foundation
import PolkadotUI
import Individuality

struct ProofOfInkVotingModel {
    let statement: MobRulePallet.Statement.ProofOfInk
    let caseIndex: MobRulePallet.CaseIndex
    let familyId: ProofOfInkPallet.FamilyId
    let votingAvailable: Bool

    let onVoting: ((Bool) -> Void)?
}
