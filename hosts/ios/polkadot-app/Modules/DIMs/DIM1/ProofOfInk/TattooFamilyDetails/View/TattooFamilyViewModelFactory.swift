import Foundation
import Individuality

protocol TattooFamilyViewModelFactoryProtocol {
    func createViewModel(
        from collections: [ProofOfInk.Collection],
        reservedDesigns: ProofOfInkPallet.ReservedDesignsResult,
        params: TattooGenerationParams,
        texts: TattooSectionMetadata.Texts
    ) -> TattooFamilyDetailsViewModel
}

final class TattooFamilyViewModelFactory {
    private let tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol
    private let userInkChoiceProvider: UserInkChoiceProviding

    init(
        tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol = TattooImageViewModelFactory(),
        userInkChoiceProvider: UserInkChoiceProviding
    ) {
        self.tattooImageViewModelFactory = tattooImageViewModelFactory
        self.userInkChoiceProvider = userInkChoiceProvider
    }
}

extension TattooFamilyViewModelFactory: TattooFamilyViewModelFactoryProtocol {
    // swiftlint:disable:next cyclomatic_complexity
    func createViewModel(
        from collections: [ProofOfInk.Collection],
        reservedDesigns: ProofOfInkPallet.ReservedDesignsResult,
        params: TattooGenerationParams,
        texts: TattooSectionMetadata.Texts
    ) -> TattooFamilyDetailsViewModel {
        let header = TattooFamilyDetailsItem.Header(
            title: texts.name,
            details: texts.description ?? ""
        )
        var items: [[TattooFamilyDetailsElement]] = [[.init(item: .header(header), action: nil)]]

        for collection in collections {
            var tattooElements = [TattooFamilyDetailsElement]()

            switch collection.family.kind {
            case let .designed(model):
                let tattoos: [TattooFamilyDetailsElement] = (0 ..< model.count)
                    .compactMap { index in
                        let reserved = reservedDesigns[collection.familyIndex] ?? []
                        guard !reserved.contains(index) else {
                            return nil
                        }
                        let choice = ProofOfInk.Choice.designed(
                            .init(
                                family: collection.familyIndex,
                                index: index,
                                familyId: collection.family.id
                            )
                        )
                        let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)
                        return TattooFamilyDetailsElement(
                            item: .tattoo(.init(image: imageViewModel)),
                            action: .selectTattoo(choice)
                        )
                    }
                tattooElements.append(contentsOf: tattoos)
            case let .procedural(procedural):
                let tattoos = (0 ... procedural.range)
                    .compactMap { (index: ProofOfInkPallet.VariantIndex) -> TattooFamilyDetailsElement? in
                        guard let choice = userInkChoiceProvider.procedural(
                            for: collection.familyIndex,
                            variantIndex: ProofOfInkPallet.VariantIndex(index),
                            familyId: collection.family.id,
                            entropy: params.entropy
                        )
                        else {
                            return nil
                        }
                        let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)
                        return TattooFamilyDetailsElement(
                            item: .tattoo(.init(image: imageViewModel)),
                            action: .selectTattoo(choice)
                        )
                    }
                tattooElements.append(contentsOf: tattoos)
            case .proceduralAccount:
                guard let choice = userInkChoiceProvider.proceduralAccount(
                    for: collection.familyIndex,
                    familyId: collection.family.id,
                    accountId: params.accountId
                ) else {
                    break
                }
                let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)
                let tattoo = TattooFamilyDetailsElement(
                    item: .tattoo(.init(image: imageViewModel)),
                    action: .selectTattoo(choice)
                )
                tattooElements.append(tattoo)
            case .proceduralPersonal:
                guard let choice = userInkChoiceProvider.proceduralPersonal(
                    for: collection.familyIndex,
                    familyId: collection.family.id,
                    personalId: params.personalId
                ) else {
                    break
                }
                let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)
                let tattoo = TattooFamilyDetailsElement(
                    item: .tattoo(.init(image: imageViewModel)),
                    action: .selectTattoo(choice)
                )
                tattooElements.append(tattoo)
            case .unsupported:
                ()
            }

            if items.count > 1 {
                var currentElements = items[1]
                currentElements.append(contentsOf: tattooElements)
                items[1] = currentElements
            } else {
                items.append(tattooElements)
            }
        }

        return .init(items: items)
    }
}
