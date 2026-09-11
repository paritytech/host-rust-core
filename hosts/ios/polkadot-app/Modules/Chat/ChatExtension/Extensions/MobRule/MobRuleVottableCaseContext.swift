import Foundation
import Individuality

struct MobRuleVottableCaseContext {
    let caseIndex: MobRulePallet.CaseIndex
    let openCase: MobRulePallet.OpenCase
    let familyId: ProofOfInkPallet.FamilyId?
    let inProgressVote: MobRuleVote?
    let isExpanded: Bool
    let sensitiveAllowed: Bool
}
