import Foundation
import PolkadotUI
import Products

/// One card as the Wallet tab draws it.
struct PocketCardViewModel: Identifiable {
    let key: PocketCardKey
    let title: String
    let privileged: Bool
    let face: CustomMessageWidgetNode?

    var id: String { key.storageId }
}

/// Assembles the collection the Wallet tab shows: the cards the host holds,
/// each with the newest face it has for them.
///
/// The face is whatever is held right now — bundled for a pinned card, approved
/// for an added one, or the last one its product drew — so the tab draws
/// immediately, offline and at cold start, without waiting on any worker.
struct PocketCardsProvider {
    private let store: any PocketCardStore
    private let resolver: any WidgetDesignTokenResolving

    init(store: any PocketCardStore, resolver: any WidgetDesignTokenResolving = WidgetDesignTokenResolver()) {
        self.store = store
        self.resolver = resolver
    }

    func cards() async -> [PocketCardViewModel] {
        var drawn: [PocketCardViewModel] = []
        for card in await store.cards() {
            let face = await store.face(for: card.key)
            drawn.append(
                PocketCardViewModel(
                    key: card.key,
                    title: card.title,
                    privileged: card.privileged,
                    face: face?.toWidgetNode(resolver: resolver)
                )
            )
        }
        return drawn
    }
}
