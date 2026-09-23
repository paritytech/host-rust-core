import Foundation
import Products
import UIKit

/// Routes `polkadot://<product>.<tld>/-/pocket/{add,open}?card=<id>`.
///
/// Ownership is decided from the reserved target, not from whether the link
/// parses: the `-` segment belongs to the host, so a malformed link under it is
/// answered here rather than falling through to the product's own App handler
/// and opening a page the user never asked for.
///
/// Classification is still the core's — `parse_navigate` screens the card id
/// the same way `remove_card` does, so a link and a removal name the same card.
final class PocketOpenService: URLHandlingServiceProtocol {
    private let parser = PocketDeeplinkParser()
    private let present: @MainActor (PocketDeeplink) -> Void
    private let refuse: @MainActor (String) -> Void

    init(
        present: @escaping @MainActor (PocketDeeplink) -> Void,
        refuse: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.present = present
        self.refuse = refuse
    }

    func handle(url: URL) -> Bool {
        guard Self.isPocketTarget(url) else { return false }

        guard let link = parser.parse(url.absoluteString),
              (try? PocketCardIdentifier.screen(link.cardId)) != nil
        else {
            Task { @MainActor in refuse(String(localized: .pocketDeeplinkMalformed)) }
            return true
        }

        Task { @MainActor in present(link) }
        return true
    }

    /// The first path segment `-` is reserved for host-handled targets and
    /// cannot be an App route.
    private static func isPocketTarget(_ url: URL) -> Bool {
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)

        return segments.count >= 2 && segments[0] == "-" && segments[1] == "pocket"
    }
}

extension PocketOpenService {
    /// The chain's Pocket handler: an add link opens the approval sheet, and an
    /// open link takes the user to the card the Pocket already holds.
    static func makeDefault(
        flowState: SPAFlowState,
        moduleNavigator: ModuleNavigating
    ) -> PocketOpenService {
        PocketOpenService(
            present: { link in
                Task { @MainActor in
                    switch link.action {
                    case .add:
                        guard let view = await PocketAddCardViewFactory.createView(
                            for: link,
                            flowState: flowState
                        ) else {
                            return
                        }
                        // Presented directly rather than through the navigator,
                        // which wraps what it is given in a navigation
                        // controller and overrides the sheet's own
                        // presentation.
                        UIWindow.topWindow?.topmostViewController?.present(view, animated: true)
                    case .open:
                        PocketCardOpening.open(
                            link: link,
                            flowState: flowState,
                            navigator: moduleNavigator
                        )
                    }
                }
            },
            refuse: { message in PocketRefusalPresenter.show(message) }
        )
    }
}
