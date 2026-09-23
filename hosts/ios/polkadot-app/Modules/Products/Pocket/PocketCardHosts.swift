import Foundation
import Products
import UIKit

/// The product hosted under an opened card.
///
/// A web view and a page load are what a card costs to open, so a card opened
/// again is worth not paying twice.
///
/// One at a time: opening another card takes the previous one down. A Pocket
/// can hold many cards, and one live web view each is not a cost worth carrying
/// for taps that may never come.
@MainActor
final class PocketCardHosts {
    static let shared = PocketCardHosts()

    private struct Held {
        let key: PocketCardKey
        let view: SPAViewProtocol
    }

    private var held: Held?

    /// The product for `key`, built by `make` unless the one already held is it.
    func view(for key: PocketCardKey, make: () -> SPAViewProtocol?) -> SPAViewProtocol? {
        if let held, held.key == key { return held.view }

        release()

        guard let view = make() else { return nil }

        held = Held(key: key, view: view)
        return view
    }

    /// Gives up a product held for a card the collection no longer has, since a
    /// card that is gone has no next tap.
    func keepOnly(_ isStillHeld: (PocketCardKey) -> Bool) {
        guard let held, !isStillHeld(held.key) else { return }

        release()
    }

    func release() {
        held = nil
    }
}
