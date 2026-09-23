import Foundation
import Products

/// Looks a card up in the worker manifest of the product that claims to back it.
///
/// Nothing here trusts the caller's spelling of the product: the resolver settles
/// on one canonical id, and that is the id the card is keyed by.
struct PublishedPocketCards: PublishedPocketCardsResolving {
    private let products: any ProductResolving
    private let debugCards: @Sendable (ProductId) -> [PocketCardDefinition]

    init(
        products: any ProductResolving,
        debugCards: @escaping @Sendable (ProductId) -> [PocketCardDefinition] = { _ in [] }
    ) {
        self.products = products
        self.debugCards = debugCards
    }

    func find(productId: ProductId, cardId: PocketCardId) async throws -> PublishedPocketCard {
        let resolved: ResolvedProduct
        do {
            resolved = try await products.resolve(productId)
        } catch {
            // A product that could not be read has not answered yet. A card
            // typed in by hand needs no chain presence and still stands;
            // anything else would settle the question against a read that
            // simply did not land.
            guard let byHand = byHand(cardId, of: productId, resolved: nil) else { throw error }

            return byHand
        }

        if let worker = resolved.executables.worker, worker.includesPocket {
            guard let definition = worker.pocketCards.first(where: { $0.id == cardId }) else {
                throw PocketPublishError.unknownCard
            }

            return PublishedPocketCard(
                productId: resolved.id,
                productName: resolved.displayName,
                workerContentId: worker.identifier,
                definition: definition
            )
        }

        // Only reached when the product publishes no Pocket worker: a published
        // one always wins, so a card supplied by hand can never shadow what a
        // product actually ships.
        guard let byHand = byHand(cardId, of: productId, resolved: resolved) else {
            throw PocketPublishError.noPocket
        }

        return byHand
    }

    private func byHand(
        _ cardId: PocketCardId,
        of productId: ProductId,
        resolved: ResolvedProduct?
    ) -> PublishedPocketCard? {
        guard let definition = debugCards(productId).first(where: { $0.id == cardId }) else { return nil }

        return PublishedPocketCard(
            productId: resolved?.id ?? productId,
            productName: resolved?.displayName ?? productId,
            workerContentId: resolved?.id ?? productId,
            definition: definition
        )
    }
}

extension PublishedPocketCards {
    /// The resolver the app uses: published manifests, with cards typed into the
    /// debug menu filling in for products that publish no worker.
    static func makeDefault(products: any ProductResolving) -> PublishedPocketCards {
        #if DEBUG
            let debug = DebugPocketCards()

            return PublishedPocketCards(products: products, debugCards: { debug.cards(for: $0) })
        #else
            return PublishedPocketCards(products: products)
        #endif
    }
}
