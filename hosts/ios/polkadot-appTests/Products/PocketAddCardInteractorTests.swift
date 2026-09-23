import Foundation
import Products
import Testing
@testable import polkadot_app

struct PocketAddCardInteractorTests {
    @Test
    func offersThePublishedCard() async throws {
        let interactor = makeInteractor(published: [loyaltyDefinition])

        let offer = try await interactor.loadOffer(productId: "game.paseo", cardId: PocketCardId(value: "loyalty"))

        #expect(offer.title == "Loyalty")
        #expect(offer.productName == "Game")
        #expect(offer.key.cardId.value == "loyalty")
    }

    /// A product whose worker does not declare Pocket has nothing to offer,
    /// however its manifest lists cards.
    @Test
    func refusesAProductThatPublishesNoPocket() async {
        let interactor = makeInteractor(published: [loyaltyDefinition], includesPocket: false)

        await #expect(throws: PocketPublishError.noPocket) {
            try await interactor.loadOffer(productId: "game.paseo", cardId: PocketCardId(value: "loyalty"))
        }
    }

    @Test
    func refusesACardTheProductDoesNotPublish() async {
        let interactor = makeInteractor(published: [loyaltyDefinition])

        await #expect(throws: PocketPublishError.unknownCard) {
            try await interactor.loadOffer(productId: "game.paseo", cardId: PocketCardId(value: "trophy"))
        }
    }

    /// The face the user approves is the one that is stored: approving keeps
    /// the offer as loaded rather than re-reading anything.
    @Test
    func approvingAddsTheCardAsUnprivileged() async throws {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([]),
            repository: InMemoryPocketCardRepository()
        )
        let interactor = makeInteractor(published: [loyaltyDefinition], store: store)
        let offer = try await interactor.loadOffer(productId: "game.paseo", cardId: PocketCardId(value: "loyalty"))

        await interactor.approve(offer)

        let stored = await store.cards()
        #expect(stored.map(\.key.cardId.value) == ["loyalty"])
        #expect(stored.first?.privileged == false)
        #expect(stored.first?.title == "Loyalty")
        #expect(await store.face(for: offer.key) == offer.face)
    }
}

// MARK: - Fixtures

private let loyaltyDefinition = PocketCardDefinition(
    id: PocketCardId(value: "loyalty"),
    title: "Loyalty",
    preview: .archive(path: "faces/loyalty.json")
)

private let minimalFace = Data("""
{ "tag": "Column", "value": { "modifiers": [], "props": {}, "children": [] } }
""".utf8)

private func makeInteractor(
    published: [PocketCardDefinition],
    includesPocket: Bool = true,
    store: any PocketCardStore = RealPocketCardStore(
        pinned: InMemoryPinnedCards([]),
        repository: InMemoryPocketCardRepository()
    )
) -> PocketAddCardInteractor {
    PocketAddCardInteractor(
        publishedCards: StubPublishedCards(
            definitions: published,
            includesPocket: includesPocket,
            productName: "Game"
        ),
        previews: PocketPreviewLoader(archive: StubArchive(), fetch: { _ in minimalFace }),
        store: store
    )
}

private struct StubPublishedCards: PublishedPocketCardsResolving {
    let definitions: [PocketCardDefinition]
    let includesPocket: Bool
    let productName: String

    func find(productId: ProductId, cardId: PocketCardId) async throws -> PublishedPocketCard {
        guard includesPocket else { throw PocketPublishError.noPocket }
        guard let definition = definitions.first(where: { $0.id == cardId }) else {
            throw PocketPublishError.unknownCard
        }
        return PublishedPocketCard(
            productId: productId,
            productName: productName,
            workerContentId: "worker.\(productId)",
            definition: definition
        )
    }
}

private struct StubArchive: PocketArchiveReading {
    func file(contentId _: ProductId, path _: String) async throws -> Data { minimalFace }
}
