import Foundation
import Operation_iOS
import SubstrateSdk
import Kingfisher
import UIKit
import Individuality

protocol TattooImageOperationMaking {
    func createDownloadOperation(
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId
    ) -> CompoundOperationWrapper<UIImage?>
}

final class TattooImageOperationFactory: TattooImageOperationMaking {
    let rendererService: ProceduralTattooRenderer
    let tattooResolver: TattooResolving
    let proceduralTattooResolver: ProceduralTattooResolving

    init(
        rendererService: ProceduralTattooRenderer = ProceduralTattooWebViewRenderer(),
        tattooResolver: TattooResolving = TattooResolutionService(),
        proceduralTattooResolver: ProceduralTattooResolving = ProceduralTattooResolverService()
    ) {
        self.rendererService = rendererService
        self.tattooResolver = tattooResolver
        self.proceduralTattooResolver = proceduralTattooResolver
    }

    func createDownloadOperation(
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId
    ) -> CompoundOperationWrapper<UIImage?> {
        switch design {
        case let .designedElective(designedElective):
            loadOperation(
                familyId: familyId,
                index: designedElective.familyIndex
            )
        case let .proceduralAccount(proceduralAccount):
            loadOperation(
                familyId: familyId,
                tattoo: .proceduralAccount(proceduralAccount.accountId)
            )
        case let .proceduralPersonal(proceduralPersonal):
            loadOperation(
                familyId: familyId,
                tattoo: .proceduralPersonal(proceduralPersonal.personalId)
            )
        case let .procedural(procedural):
            loadOperation(
                familyId: familyId,
                tattoo: .procedural(procedural.proceduralSeed)
            )
        }
    }

    func loadOperation(
        familyId: ProofOfInkPallet.FamilyId,
        index: ProofOfInkPallet.DesignIndex
    ) -> CompoundOperationWrapper<UIImage?> {
        let resolveInputOperation = AsyncClosureOperation { [tattooResolver] handler in
            tattooResolver.resolveImageUrl(for: familyId, index: index, completion: handler)
        }

        let loadOperation = AsyncClosureOperation<UIImage?> { handler in
            let url = try resolveInputOperation.extractNoCancellableResultData()
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case let .success(data):
                    handler(.success(data.image))
                case let .failure(error):
                    handler(.failure(error))
                }
            }
        }
        loadOperation.addDependency(resolveInputOperation)

        return CompoundOperationWrapper(
            targetOperation: loadOperation,
            dependencies: [resolveInputOperation]
        )
    }

    func loadOperation(
        familyId: ProofOfInkPallet.FamilyId,
        tattoo: ProceduralTattoo
    ) -> CompoundOperationWrapper<UIImage?> {
        let resolveInputOperation = AsyncClosureOperation { [proceduralTattooResolver] handler in
            proceduralTattooResolver.resolveImageUrl(for: familyId, for: tattoo, completion: handler)
        }

        let loadOperation = AsyncClosureOperation { [rendererService] handler in
            let input = try resolveInputOperation.extractNoCancellableResultData()
            let provider = ProceduralTattooImageProvider(renderer: rendererService, input: input)
            provider.data(handler: handler)
        }
        loadOperation.addDependency(resolveInputOperation)

        let convertToImageOperation = ClosureOperation {
            let data = try loadOperation.extractNoCancellableResultData()
            let image = UIImage(data: data)
            return image
        }
        convertToImageOperation.addDependency(loadOperation)

        return CompoundOperationWrapper(
            targetOperation: convertToImageOperation,
            dependencies: [resolveInputOperation, loadOperation]
        )
    }
}
