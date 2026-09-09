import Foundation
import Individuality

protocol TattooListViewModelFactoryProtocol {
    func createListViewModel(
        from familyIndex: ProofOfInkPallet.FamilyIndex,
        family: ProofOfInkPallet.Family,
        reserved: Set<ProofOfInkPallet.DesignIndex>,
        metadata: TattooMetadata.Info,
        params: TattooGenerationParams
    ) -> TattooListViewModel?

    func createListViewModel(
        from familyIndices: [ProofOfInkPallet.FamilyIndex],
        families: [ProofOfInkPallet.Family],
        reservedDesigns: ProofOfInkPallet.ReservedDesignsResult,
        params: TattooGenerationParams,
        texts: TattooSectionMetadata.Texts
    ) -> TattooListViewModel?
}

final class TattooListViewModelFactory {
    private enum Constants {
        static let maxNumberPerFamily = 3
    }

    private let tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol
    private let userInkChoiceProvider: UserInkChoiceProviding

    init(
        tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol = TattooImageViewModelFactory(),
        userInkChoiceProvider: UserInkChoiceProviding
    ) {
        self.tattooImageViewModelFactory = tattooImageViewModelFactory
        self.userInkChoiceProvider = userInkChoiceProvider
    }

    private func createDesignedViewModel(
        from model: ProofOfInkPallet.FamilyKind.Designed,
        familyIndex: ProofOfInkPallet.FamilyIndex,
        family: ProofOfInkPallet.Family,
        reserved: Set<ProofOfInkPallet.DesignIndex>,
        texts: TattooSectionMetadata.Texts
    ) -> TattooListViewModel? {
        let items = model
            .fetchFirst(numberOfItems: Constants.maxNumberPerFamily, reserved: reserved)
            .map { index in
                let choice = ProofOfInk.Choice.designed(.init(
                    family: familyIndex,
                    index: index,
                    familyId: family.id
                ))
                let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)
                return TattooListViewModel.Item(image: imageViewModel, choice: choice)
            }

        guard !items.isEmpty else {
            return nil
        }

        let availableCount = Int(model.count) - reserved.count

        return TattooListViewModel(
            indices: [familyIndex],
            metadata: .init(
                texts: texts,
                numberOfItems: availableCount
            ),
            items: items
        )
    }

    private func createProcedural(
        from model: ProofOfInkPallet.FamilyKind.Procedural,
        familyIndex: ProofOfInkPallet.FamilyIndex,
        family: ProofOfInkPallet.Family,
        params: TattooGenerationParams,
        texts: TattooSectionMetadata.Texts
    ) -> TattooListViewModel? {
        let items = (0 ... min(model.range, ProofOfInkPallet.VariantIndex(Constants.maxNumberPerFamily) - 1))
            .compactMap { (index: ProofOfInkPallet.VariantIndex) -> TattooListViewModel.Item? in
                guard let choice = userInkChoiceProvider.procedural(
                    for: familyIndex,
                    variantIndex: index,
                    familyId: family.id,
                    entropy: params.entropy
                ) else {
                    return nil
                }
                let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)
                return TattooListViewModel.Item(
                    image: imageViewModel,
                    choice: choice
                )
            }
        return TattooListViewModel(
            indices: [familyIndex],
            metadata: .init(texts: texts, numberOfItems: Int(model.range) + 1),
            items: items
        )
    }

    private func createProceduralAccount(
        from familyIndex: ProofOfInkPallet.FamilyIndex,
        family: ProofOfInkPallet.Family,
        params: TattooGenerationParams,
        texts: TattooSectionMetadata.Texts
    ) -> TattooListViewModel? {
        guard
            let choice = userInkChoiceProvider.proceduralAccount(
                for: familyIndex,
                familyId: family.id,
                accountId: params.accountId
            ) else {
            return nil
        }

        let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)
        return TattooListViewModel(
            indices: [familyIndex],
            metadata: .init(texts: texts, numberOfItems: 1),
            items: [.init(image: imageViewModel, choice: choice)]
        )
    }

    private func createProceduralPersonal(
        from familyIndex: ProofOfInkPallet.FamilyIndex,
        family: ProofOfInkPallet.Family,
        params: TattooGenerationParams,
        texts: TattooSectionMetadata.Texts
    ) -> TattooListViewModel? {
        guard
            let choice = userInkChoiceProvider.proceduralPersonal(
                for: familyIndex,
                familyId: family.id,
                personalId: params.personalId
            ) else {
            return nil
        }

        let imageViewModel = tattooImageViewModelFactory.createViewModelFromChoice(choice)

        return TattooListViewModel(
            indices: [familyIndex],
            metadata: .init(texts: texts, numberOfItems: 1),
            items: [.init(image: imageViewModel, choice: choice)]
        )
    }
}

extension TattooListViewModelFactory: TattooListViewModelFactoryProtocol {
    func createListViewModel(
        from familyIndex: ProofOfInkPallet.FamilyIndex,
        family: ProofOfInkPallet.Family,
        reserved: Set<ProofOfInkPallet.DesignIndex>,
        metadata: TattooMetadata.Info,
        params: TattooGenerationParams
    ) -> TattooListViewModel? {
        switch family.kind {
        case let .designed(model):
            createDesignedViewModel(
                from: model,
                familyIndex: familyIndex,
                family: family,
                reserved: reserved,
                texts: .init(metadataInfo: metadata)
            )
        case let .procedural(procedural):
            createProcedural(
                from: procedural,
                familyIndex: familyIndex,
                family: family,
                params: params,
                texts: .init(metadataInfo: metadata)
            )
        case .proceduralAccount:
            createProceduralAccount(
                from: familyIndex,
                family: family,
                params: params,
                texts: .init(metadataInfo: metadata)
            )
        case .proceduralPersonal:
            createProceduralPersonal(
                from: familyIndex,
                family: family,
                params: params,
                texts: .init(metadataInfo: metadata)
            )
        case .unsupported:
            nil
        }
    }

    func createListViewModel(
        from familyIndices: [ProofOfInkPallet.FamilyIndex],
        families: [ProofOfInkPallet.Family],
        reservedDesigns: ProofOfInkPallet.ReservedDesignsResult,
        params: TattooGenerationParams,
        texts: TattooSectionMetadata.Texts
    ) -> TattooListViewModel? {
        guard families.count == familyIndices.count, !families.isEmpty else {
            return nil
        }

        var items = [TattooListViewModel.Item]()

        for (index, family) in families.enumerated() {
            let reserved = reservedDesigns[familyIndices[index]] ?? []

            switch family.kind {
            case let .designed(model):
                items.append(contentsOf: createDesignedViewModel(
                    from: model,
                    familyIndex: familyIndices[index],
                    family: family,
                    reserved: reserved,
                    texts: texts
                )?.items ?? [])
            case let .procedural(procedural):
                items.append(contentsOf: createProcedural(
                    from: procedural,
                    familyIndex: familyIndices[index],
                    family: family,
                    params: params,
                    texts: texts
                )?.items ?? [])
            case .proceduralAccount:
                items.append(contentsOf: createProceduralAccount(
                    from: familyIndices[index],
                    family: family,
                    params: params,
                    texts: texts
                )?.items ?? [])
            case .proceduralPersonal:
                items.append(contentsOf: createProceduralPersonal(
                    from: familyIndices[index],
                    family: family,
                    params: params,
                    texts: texts
                )?.items ?? [])
            case .unsupported:
                break
            }
        }

        guard !items.isEmpty else {
            return nil
        }

        let metadata = TattooSectionMetadata(
            texts: texts,
            numberOfItems: items.count
        )

        return .init(
            indices: familyIndices,
            metadata: metadata,
            items: items
        )
    }
}
