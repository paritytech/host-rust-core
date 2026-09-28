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

    /// What draws `productId`'s cards right now.
    static func current(
        for productId: ProductId,
        facade: TrUAPIWorkerFacade = .shared
    ) -> PocketCardDrawing {
        PocketCardDrawing(
            faces: facade.faces,
            images: facade.images(of: productId),
            installation: facade.installation
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
