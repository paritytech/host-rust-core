import Foundation
import Products
import UIKit

/// Opens the card's product, at the page the card names.
///
/// The protocol names the widget as what an expanded card runs, so that is the
/// executable served here. The origin stays the product's base domain, so the
/// card sees the same grants and storage its worker does.
@MainActor
enum PocketCardOpening {
    static func open(
        _ key: PocketCardKey,
        flowState: SPAFlowState,
        navigator: ModuleNavigating,
        hosts: PocketCardHosts = .shared
    ) {
        guard let url = key.launchUrl, let page = flowState.hostProvider.page(url: url) else { return }

        let view = hosts.view(for: key) {
            let configuration = SPAConfiguration(
                title: nil,
                isRootScreen: false,
                showMoreButton: true,
                page: page,
                executable: .widget
            )

            return SPAViewFactory.createView(configuration: configuration, flowState: flowState)
        }

        guard let view else { return }

        navigator.presentFullScreen(view.controller)
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
            guard let store = await pocket.store(), await store.cards().contains(where: { $0.key == key }) else {
                PocketRefusalPresenter.show(String(localized: .pocketDeeplinkUnknownCard))
                return
            }

            open(key, flowState: flowState, navigator: navigator)
        }
    }
}
