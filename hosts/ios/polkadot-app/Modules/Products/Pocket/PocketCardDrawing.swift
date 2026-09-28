import Foundation
import Products

/// What a card is drawn from: the faces its product streams, and how the images
/// inside them are read.
///
/// Carried as one value with the installation it came from, so a card can be
/// keyed on it. A session installs a whole new Pocket at once, and a card keyed
/// only on its own id would go on iterating the stream the previous session
/// ended, leaving it on the face it last drew.
struct PocketCardDrawing {
    let faces: (any PocketFaceSourcing)?
    let images: PocketImageResolver?
    /// Which installation these came from. Cards read it rather than compare
    /// the sources themselves, which are values and carry no identity.
    let installation: Int

    /// What draws `productId`'s cards right now, from the session's Pocket.
    @MainActor
    static func current(for productId: ProductId, pocket: PocketService? = nil) -> PocketCardDrawing {
        guard let pocket = pocket ?? .current else {
            return PocketCardDrawing(faces: nil, images: nil, installation: 0)
        }

        return PocketCardDrawing(
            faces: pocket.faces,
            images: pocket.images(of: productId),
            installation: pocket.installation
        )
    }

    /// What a card's drawing task is keyed on: the card, and the Pocket it is
    /// being drawn from.
    func key(for cardId: String) -> Key {
        Key(cardId: cardId, installation: installation)
    }

    struct Key: Equatable {
        let cardId: String
        let installation: Int
    }
}
