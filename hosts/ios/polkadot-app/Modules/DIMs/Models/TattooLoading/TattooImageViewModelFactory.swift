import Foundation
import Individuality
import PolkadotUI

protocol TattooImageViewModelFactoryProtocol {
    func createViewModelFromInkSpec(_ design: ProofOfInkPallet.InkSpec, familyId: ProofOfInkPallet.FamilyId)
        -> ImageViewModelProtocol?
    func createViewModelFromChoice(_ design: ProofOfInk.Choice) -> ImageViewModelProtocol?
}

final class TattooImageViewModelFactory {
    private let proceduralTattooRenderer: ProceduralTattooRenderer

    init(
        proceduralTattooRenderer: ProceduralTattooRenderer = ProceduralTattooWebViewRenderer()
    ) {
        self.proceduralTattooRenderer = proceduralTattooRenderer
    }
}

extension TattooImageViewModelFactory: TattooImageViewModelFactoryProtocol {
    func createViewModelFromInkSpec(
        _ design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId
    ) -> ImageViewModelProtocol? {
        switch design {
        case let .designedElective(designedElective):
            DesignedTattooViewModel(
                familyId: familyId,
                designIndex: designedElective.design
            )
        case let .proceduralAccount(proceduralAccount):
            ProceduralTattooViewModel(
                familyId: familyId,
                tattoo: .proceduralAccount(proceduralAccount.accountId),
                rendererService: proceduralTattooRenderer
            )
        case let .proceduralPersonal(proceduralPersonal):
            ProceduralTattooViewModel(
                familyId: familyId,
                tattoo: .proceduralPersonal(proceduralPersonal.personalId),
                rendererService: proceduralTattooRenderer
            )
        case let .procedural(procedural):
            ProceduralTattooViewModel(
                familyId: familyId,
                tattoo: .procedural(procedural.proceduralSeed),
                rendererService: proceduralTattooRenderer
            )
        }
    }

    func createViewModelFromChoice(_ design: ProofOfInk.Choice) -> ImageViewModelProtocol? {
        switch design {
        case let .designed(designed):
            DesignedTattooViewModel(
                familyId: designed.familyId,
                designIndex: designed.index
            )
        case let .proceduralAccount(proceduralAccount):
            ProceduralTattooViewModel(
                familyId: proceduralAccount.familyId,
                tattoo: .proceduralAccount(proceduralAccount.accountId),
                rendererService: proceduralTattooRenderer
            )
        case let .proceduralPersonal(proceduralPersonal):
            ProceduralTattooViewModel(
                familyId: proceduralPersonal.familyId,
                tattoo: .proceduralPersonal(proceduralPersonal.personalId),
                rendererService: proceduralTattooRenderer
            )
        case let .procedural(procedural):
            ProceduralTattooViewModel(
                familyId: procedural.familyId,
                tattoo: .procedural(procedural.proceduralSeed),
                rendererService: proceduralTattooRenderer
            )
        }
    }
}
