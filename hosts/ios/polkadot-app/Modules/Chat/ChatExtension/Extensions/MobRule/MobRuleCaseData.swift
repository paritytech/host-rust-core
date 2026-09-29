import Foundation
import Individuality

enum MobRuleCaseData: Equatable, Codable {
    case open(MobRulePallet.OpenCase)
    case ripe(MobRulePallet.RipeCase)
    case done(MobRulePallet.DoneCase)
}

extension MobRuleCaseData {
    var caseDetails: MobRulePallet.CaseDetails? {
        switch self {
        case let .open(openCase):
            openCase.details
        case let .ripe(ripeCase):
            ripeCase.details
        case .done:
            nil
        }
    }

    var tally: MobRulePallet.VoteTally? {
        switch self {
        case let .open(openCase):
            openCase.tally
        case .ripe,
             .done:
            nil
        }
    }
}
