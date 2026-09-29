import Foundation
import Individuality
import PolkadotUI
import UIKit

final class TattooChatMessageMediaPreviewProvider {
    private let design: ProofOfInkPallet.InkSpec
    private let familyId: ProofOfInkPallet.FamilyId
    private let tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol
    private lazy var viewModel = tattooImageViewModelFactory.createViewModelFromInkSpec(
        design,
        familyId: familyId
    )

    init(
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        tattooImageViewModelFactory: TattooImageViewModelFactoryProtocol = TattooImageViewModelFactory()
    ) {
        self.design = design
        self.familyId = familyId
        self.tattooImageViewModelFactory = tattooImageViewModelFactory
    }
}

extension TattooChatMessageMediaPreviewProvider: ChatMessageMediaPreviewProviding {
    var identifier: String {
        "tattoo::\(familyId)_\(design)"
    }

    func providePreview(
        for imageView: UIImageView,
        size: CGSize?
    ) {
        guard let viewModel else {
            return
        }

        let resolvedSize = size ?? CGSize(width: 512, height: 512) // fallback size
        let settings = ImageViewModelSettings(targetSize: resolvedSize)
        viewModel.loadImage(
            on: imageView,
            settings: settings,
            animated: true,
            completion: nil
        )
    }
}
