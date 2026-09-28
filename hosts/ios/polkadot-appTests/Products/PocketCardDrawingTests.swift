import Foundation
import Products
import Testing
@testable import polkadot_app

/// A card keyed only on its own id keeps the stream it started, and a sign-out
/// and back in ends that stream without starting another: the card is left on
/// whatever it last drew, for as long as it is on screen.
struct PocketCardDrawingTests {
    @Test
    func tellsANewPocketApartFromTheOneTheCardWasDrawingFrom() {
        let first = PocketCardDrawing(faces: nil, images: nil, installation: 1)
        let second = PocketCardDrawing(faces: nil, images: nil, installation: 2)

        #expect(first.key(for: "loyalty") != second.key(for: "loyalty"))
    }

    /// Two cards of one Pocket are told apart by their own ids, so one card
    /// redrawing does not restart the other.
    @Test
    func tellsTwoCardsOfOnePocketApart() {
        let drawing = PocketCardDrawing(faces: nil, images: nil, installation: 1)

        #expect(drawing.key(for: "loyalty") != drawing.key(for: "streak"))
        #expect(drawing.key(for: "loyalty") == drawing.key(for: "loyalty"))
    }
}
