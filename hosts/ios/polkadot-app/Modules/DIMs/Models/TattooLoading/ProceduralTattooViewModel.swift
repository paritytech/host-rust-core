import Foundation
import Kingfisher
import UIKit
import PolkadotUI
import Individuality

final class ProceduralTattooViewModel {
    let familyId: ProofOfInkPallet.FamilyId
    let tattoo: ProceduralTattoo
    let resolutionService: ProceduralTattooResolving
    let rendererService: ProceduralTattooRenderer
    private let optionsFactory: ImageProcessingOptionsProducing

    init(
        familyId: ProofOfInkPallet.FamilyId,
        tattoo: ProceduralTattoo,
        resolutionService: ProceduralTattooResolving = ProceduralTattooResolverService(),
        optionsFactory: ImageProcessingOptionsProducing = ImageProcessingOptionsFactory(),
        rendererService: ProceduralTattooRenderer
    ) {
        self.familyId = familyId
        self.tattoo = tattoo
        self.resolutionService = resolutionService
        self.optionsFactory = optionsFactory
        self.rendererService = rendererService
    }
}

extension ProceduralTattooViewModel: ImageViewModelProtocol {
    @MainActor func loadImage(
        on imageView: UIImageView,
        settings: ImageViewModelSettings,
        animated: Bool,
        completion: ((Bool) -> Void)?
    ) {
        resolutionService.resolveImageUrl(for: familyId, for: tattoo) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(input):
                let provider = ProceduralTattooImageProvider(renderer: rendererService, input: input)
                let options = optionsFactory.options(for: settings, animated: animated)
                imageView.kf.setImage(with: provider, options: options) { result in
                    switch result {
                    case .success:
                        completion?(true)
                    case .failure:
                        completion?(false)
                    }
                }
            case .failure:
                completion?(false)
            }
        }
    }

    @MainActor func cancel(on imageView: UIImageView) {
        imageView.image = nil
    }
}
