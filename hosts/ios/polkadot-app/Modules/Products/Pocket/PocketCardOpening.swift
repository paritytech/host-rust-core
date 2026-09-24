import Foundation
import Products
import UIKit

/// Opens the card's product, at the page the card names, on a screen the card
/// itself heads.
///
/// The protocol names the widget as what an expanded card runs, so that is the
/// executable served here. The origin stays the product's base domain, so the
/// card sees the same grants and storage its worker does.
@MainActor
enum PocketCardOpening {
    static func open(
        _ card: PocketCardViewModel,
        flowState: SPAFlowState,
        navigator: ModuleNavigating
    ) {
        guard
            let url = card.key.launchUrl,
            let page = flowState.hostProvider.page(url: url)
        else { return }

        let product = PocketCardHosts.shared.view(for: card.key) {
            let configuration = SPAConfiguration(
                title: card.title,
                isRootScreen: false,
                showMoreButton: false,
                page: page,
                executable: .widget
            )

            return SPAViewFactory.createView(configuration: configuration, flowState: flowState)
        }

        guard let product else { return }

        navigator.presentFullScreen(PocketCardScreenViewController(card: card, product: product))
    }

    /// A link may name a card the Pocket does not hold, which is the one case
    /// the user is told about rather than silently taken into the product.
    static func open(
        link: PocketDeeplink,
        flowState: SPAFlowState,
        navigator: ModuleNavigating,
        pocket: PocketFacade = .shared
    ) {
        guard let cardId = try? PocketCardIdentifier.screen(link.cardId) else {
            PocketRefusalPresenter.show(String(localized: .pocketDeeplinkMalformed))
            return
        }

        let key = PocketCardKey(productId: link.productHost, cardId: cardId)

        Task { @MainActor in
            guard
                let store = await pocket.store(),
                let card = await PocketCardsProvider(store: store).card(for: key)
            else {
                PocketRefusalPresenter.show(String(localized: .pocketDeeplinkUnknownCard))
                return
            }

            open(card, flowState: flowState, navigator: navigator)
        }
    }
}
