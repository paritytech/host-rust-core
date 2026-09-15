import Foundation
import UIKit
import Operation_iOS
import PolkadotUI
import Individuality

final class DesignedTattooViewModel {
    let familyId: ProofOfInkPallet.FamilyId
    let designIndex: ProofOfInkPallet.DesignIndex
    let resolutionService: TattooResolving

    private var imageViewModel: ImageViewModelProtocol?

    init(
        familyId: ProofOfInkPallet.FamilyId,
        designIndex: ProofOfInkPallet.DesignIndex,
        resolutionService: TattooResolving = TattooResolutionService()
    ) {
        self.familyId = familyId
        self.designIndex = designIndex
        self.resolutionService = resolutionService
    }

    @MainActor
    private func loadExisting(
        viewModel: ImageViewModelProtocol,
        imageView: UIImageView,
        settings: ImageViewModelSettings,
        animated: Bool,
        completion: ((Bool) -> Void)?
    ) {
        viewModel.loadImage(on: imageView, settings: settings, animated: animated, completion: completion)
    }
}

extension DesignedTattooViewModel: ImageViewModelProtocol {
    func loadImage(
        on imageView: UIImageView,
        settings: ImageViewModelSettings,
        animated: Bool,
        completion: ((Bool) -> Void)?
    ) {
        if let imageViewModel {
            loadExisting(
                viewModel: imageViewModel,
                imageView: imageView,
                settings: settings,
                animated: animated,
                completion: completion
            )
        } else {
            _ = resolutionService.resolveImageUrl(
                for: familyId,
                index: designIndex
            ) { [weak self] result in
                guard let self else {
                    completion?(false)
                    return
                }

                switch result {
                case let .success(url):
                    let imageViewModel = RemoteImageViewModel(url: url)
                    self.imageViewModel = imageViewModel
                    loadExisting(
                        viewModel: imageViewModel,
                        imageView: imageView,
                        settings: settings,
                        animated: true,
                        completion: completion
                    )

                case .failure:
                    completion?(false)
                }
            }
        }
    }

    func cancel(on imageView: UIImageView) {
        imageViewModel?.cancel(on: imageView)
    }
}
