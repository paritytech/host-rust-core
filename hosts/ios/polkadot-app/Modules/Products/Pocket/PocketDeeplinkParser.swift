import Foundation
import TrUAPIHost

/// Named to avoid the core's own `PocketDeeplinkAction`: a file importing both
/// cannot tell them apart, and the collision crashes the type checker rather
/// than producing a diagnostic.
enum PocketLinkAction: Equatable {
    case add
    case open
}

/// A `/-/pocket/<action>?card=<id>` link as the core classifies it.
/// `productHost` is the lower-cased dotNS name.
struct PocketDeeplink: Equatable {
    let productHost: String
    let action: PocketLinkAction
    let cardId: String
    /// The normalized `polkadot://` form, with the card id percent-encoded, so
    /// re-parsing it names the same card.
    let canonicalUrl: String
}

/// Classifies through the core's `parse_navigate`, so every host reads a Pocket
/// link the same way. Kept behind this adapter, like the host bridges, so a
/// bindgen rename does not ripple through the app.
struct PocketDeeplinkParser {
    func parse(_ url: String) -> PocketDeeplink? {
        guard case let .pocket(identifier, action, cardId, canonicalUrl) = parseNavigate(input: url) else {
            return nil
        }

        let linkAction: PocketLinkAction =
            switch action {
            case .add: .add
            case .open: .open
            }

        return PocketDeeplink(
            productHost: identifier,
            action: linkAction,
            cardId: cardId,
            canonicalUrl: canonicalUrl
        )
    }
}
