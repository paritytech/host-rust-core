import Foundation
import Operation_iOS
import SubstrateSdk
import Individuality
import UIKit

protocol TattooImageProviding {
    func provideImage() -> CompoundOperationWrapper<UIImage?>
}

final class TattooImageProvider {
    let design: ProofOfInkPallet.InkSpec
    let familyId: ProofOfInkPallet.FamilyId
    let factory: TattooImageOperationMaking

    init(
        design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        factory: TattooImageOperationMaking = TattooImageOperationFactory()
    ) {
        self.design = design
        self.familyId = familyId
        self.factory = factory
    }
}

extension TattooImageProvider: TattooImageProviding {
    func provideImage() -> CompoundOperationWrapper<UIImage?> {
        factory.createDownloadOperation(design: design, familyId: familyId)
    }
}
