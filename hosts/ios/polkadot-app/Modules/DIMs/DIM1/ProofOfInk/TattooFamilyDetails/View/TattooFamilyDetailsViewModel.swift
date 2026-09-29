import Foundation
import Individuality
import PolkadotUI

enum TattooFamilyDetailsItem {
    struct Tattoo {
        let image: ImageViewModelProtocol?
    }

    struct Header: Equatable {
        let title: String
        let details: String
    }

    case header(Header)
    case tattoo(Tattoo)
}

enum TattooFamilyDetailsAction: Equatable {
    case selectTattoo(ProofOfInk.Choice)
}

struct TattooFamilyDetailsElement {
    let item: TattooFamilyDetailsItem
    let action: TattooFamilyDetailsAction?
}

struct TattooFamilyDetailsViewModel {
    let items: [[TattooFamilyDetailsElement]]
}
