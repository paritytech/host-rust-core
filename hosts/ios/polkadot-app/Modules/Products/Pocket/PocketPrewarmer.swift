import Foundation
import Products

/// Fetches the archive a host-placed card's product loads from, before the user
/// presses the card.
///
/// Pressing a card opens its product, and the archive is the slow part of that:
/// a chain read and a content fetch. Doing it while the collection is on screen
/// turns the press into a load from disk.
///
/// Host-placed cards only. They are few and fixed, where a Pocket full of added
/// cards would turn one visit to the tab into a fetch per product — which is
/// the opposite of what this is for.
@MainActor
final class PocketPrewarmer {
    private let products: any ProductResolving
    private let dotNsResolver: any DotNsResolverProtocol
    private let logger: LoggerProtocol

    /// Only products whose archive is now on disk. A warm that failed left
    /// nothing there, so the next visit tries again rather than leaving the
    /// card slow for the rest of the run.
    private var warmed: Set<ProductId> = []

    init(
        products: any ProductResolving,
        dotNsResolver: any DotNsResolverProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.products = products
        self.dotNsResolver = dotNsResolver
        self.logger = logger
    }

    func warm(_ cards: [PocketCardViewModel]) async {
        let pending = Set(cards.filter(\.privileged).map(\.key.productId)).subtracting(warmed)

        for productId in pending {
            await warm(productId)
        }
    }

    private func warm(_ productId: ProductId) async {
        do {
            let contentId = try await products.resolve(productId).appContentId
            _ = try await dotNsResolver.resolveToLocalURL(dotNsName: contentId)
            warmed.insert(productId)
            logger.debug("[pocket] warmed \(productId)'s archive")
        } catch {
            logger.error("[pocket] could not warm \(productId)'s archive: \(error)")
        }
    }
}
