import Foundation
import Products
import Testing
@testable import polkadot_app

struct PocketAddCardInteractorTests {
    @Test
    func offersThePublishedCard() async throws {
        let interactor = makeAddCardInteractor(published: [loyaltyDefinition])

        let offer = try await interactor.loadOffer(productId: "game.paseo", cardId: PocketCardId(value: "loyalty"))

        #expect(offer.title == "Loyalty")
        #expect(offer.productName == "Game")
        #expect(offer.key.cardId.value == "loyalty")
    }

    /// A product whose worker does not declare Pocket has nothing to offer,
    /// however its manifest lists cards.
    @Test
    func refusesAProductThatPublishesNoPocket() async {
        let interactor = makeAddCardInteractor(published: [loyaltyDefinition], includesPocket: false)

        await #expect(throws: PocketPublishError.noPocket) {
            try await interactor.loadOffer(productId: "game.paseo", cardId: PocketCardId(value: "loyalty"))
        }
    }

    @Test
    func refusesACardTheProductDoesNotPublish() async {
        let interactor = makeAddCardInteractor(published: [loyaltyDefinition])

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
        let interactor = makeAddCardInteractor(published: [loyaltyDefinition], store: store)
        let offer = try await interactor.loadOffer(productId: "game.paseo", cardId: PocketCardId(value: "loyalty"))

        await interactor.approve(offer)

        let stored = try await store.cards()
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
