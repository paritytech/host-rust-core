import Foundation
import Products

/// Opens the product a card belongs to, at the page the card names.
///
/// This is what a card press does, and what a `pocket/open` link asks for: the
/// card is the way into the product, so pressing one lands on the product's own
/// page rather than on a screen the host made up.
@MainActor
enum PocketCardOpening {
    static func open(_ key: PocketCardKey, hostProvider: any ProductHostProviding, navigator: ModuleNavigating) {
        guard let url = key.launchUrl, let page = hostProvider.page(url: url) else { return }

        navigator.openProduct(page: page)
    }

    /// A link may name a card the Pocket does not hold, which is the one case
    /// the user is told about rather than silently taken into the product.
    static func open(
        link: PocketDeeplink,
        hostProvider: any ProductHostProviding,
        navigator: ModuleNavigating,
        pocket: PocketFacade = .shared
    ) {
        guard let cardId = try? PocketCardIdentifier.screen(link.cardId) else {
            PocketRefusalPresenter.show(String(localized: .pocketDeeplinkMalformed))
            return
        }

        let key = PocketCardKey(productId: link.productHost, cardId: cardId)

        Task { @MainActor in
            guard let store = await pocket.store(), await store.cards().contains(where: { $0.key == key }) else {
                PocketRefusalPresenter.show(String(localized: .pocketDeeplinkUnknownCard))
                return
            }

            open(key, hostProvider: hostProvider, navigator: navigator)
        }
    }
}
