import Foundation

public extension ProofOfInk.Choice {
    func toRemote() -> ProofOfInkPallet.InkChoice {
        switch self {
        case let .designed(designed):
            ProofOfInkPallet.InkChoice.designedElective(.init(
                familyIndex: designed.family,
                designIndex: designed.index
            ))
        case let .proceduralAccount(proceduralAccount):
            ProofOfInkPallet.InkChoice.proceduralAccount(proceduralAccount.family)
        case let .proceduralPersonal(proceduralPersonal):
            ProofOfInkPallet.InkChoice.proceduralPersonal(proceduralPersonal.family)
        case let .procedural(procedural):
            ProofOfInkPallet.InkChoice.procedural(.init(
                familyIndex: procedural.family,
                variantIndex: procedural.variantIndex
            ))
        }
    }
}
