import Foundation

struct CollectionInput: Encodable {
    let owned: [OwnedNft]
    let displayName: String?

    struct OwnedNft: Encodable {
        let hash: String
        let mintedAt: Int?
        let pending: Bool?
    }
}
