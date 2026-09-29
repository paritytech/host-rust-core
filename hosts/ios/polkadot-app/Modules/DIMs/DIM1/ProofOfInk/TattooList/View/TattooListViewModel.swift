import Foundation
import Individuality
import PolkadotUI

struct TattooListViewModel {
    struct Item {
        let image: ImageViewModelProtocol?
        let choice: ProofOfInk.Choice
    }

    let indices: [ProofOfInkPallet.FamilyIndex]
    let metadata: TattooSectionMetadata
    let items: [Item]
}

enum TattooListStateViewModel {
    case applied
    case applyWithDeposit
    case insufficientDeposit

    var isUnlocked: Bool {
        switch self {
        case .applied:
            true
        case .insufficientDeposit,
             .applyWithDeposit:
            false
        }
    }
}

struct TattooSectionMetadata {
    struct Texts {
        let name: String
        let description: String?
    }

    let texts: Texts
    let numberOfItems: Int
}

extension TattooSectionMetadata.Texts {
    init(metadataInfo: TattooMetadata.Info) {
        name = metadataInfo.name
        description = metadataInfo.description
    }
}
