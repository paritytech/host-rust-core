import Foundation
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

/// Serves one product's slice of the collection to the core. Both callbacks are
/// answered synchronously on the core's own dispatcher thread.
struct ProductPocketHostBridgeTests {
    @Test
    func listsOnlyTheCallingProductsCards() async throws {
        let bridge = await makeBridge(stored: [loyalty, otherProductCard])

        #expect(try bridge.listCards().map(\.cardId) == ["loyalty"])
    }

    @Test
    func reportsWhetherTheHostPinnedACard() async throws {
        let bridge = await makeBridge(productId: humanity.key.productId, pinned: [humanity])

        #expect(try bridge.listCards().first?.privileged == true)
    }

    /// A privileged card is refused without touching storage, and the refusal
    /// is a distinct outcome rather than a thrown error.
    @Test
    func refusesToRemoveAPinnedCard() async throws {
        let bridge = await makeBridge(productId: humanity.key.productId, pinned: [humanity])

        #expect(try bridge.removeCard(cardId: "humanity") == NativePocketRemoval.privileged)
    }

    @Test
    func removesACardTheProductOwns() async throws {
        let repository = InMemoryPocketCardRepository()
        await repository.insert(loyalty, face: .nil)
        let bridge = await makeBridge(repository: repository)

        #expect(try bridge.removeCard(cardId: "loyalty") == NativePocketRemoval.removed)
        #expect(try bridge.listCards().isEmpty)
    }

    /// Removing a card that is not held is a success the core tells apart from
    /// one the host performed.
    @Test
    func removingAnAbsentCardIsAbsentNotAnError() async throws {
        let bridge = await makeBridge()

        #expect(try bridge.removeCard(cardId: "loyalty") == NativePocketRemoval.absent)
    }

    /// A product cannot reach another product's card through its own bridge,
    /// even by naming it exactly.
    @Test
    func cannotRemoveAnotherProductsCard() async throws {
        let repository = InMemoryPocketCardRepository()
        await repository.insert(otherProductCard, face: .nil)
        let bridge = await makeBridge(repository: repository)

        #expect(try bridge.removeCard(cardId: "trophy") == NativePocketRemoval.absent)
        #expect(await repository.cards().count == 1)
    }

    /// The core is told only when this product's own slice changes. A face
    /// streaming at frame rate changes the stored collection continuously
    /// without changing any card the core knows about.
    @Test
    func republishesOnlyWhenItsOwnSliceChanges() async throws {
        let repository = InMemoryPocketCardRepository()
        let bridge = await makeBridge(repository: repository)
        let published = Published()
        bridge.start { published.record($0) }

        await repository.insert(loyalty, face: .nil)
        await bridge.refresh()
        await repository.insert(otherProductCard, face: .nil)
        await bridge.refresh()

        #expect(published.counts == [1])
    }
}

// MARK: - Fixtures

private let loyalty = PocketCardEntry(
    key: PocketCardKey(productId: "game.paseo", cardId: PocketCardId(value: "loyalty")),
    title: "Loyalty",
    privileged: false
)

private let otherProductCard = PocketCardEntry(
    key: PocketCardKey(productId: "shop.paseo", cardId: PocketCardId(value: "trophy")),
    title: "Trophy",
    privileged: false
)

private let humanity = PocketCardEntry(
    key: PocketCardKey(productId: "peopl.paseo", cardId: PocketCardId(value: "humanity")),
    title: "Humanity",
    privileged: true
)

private func makeBridge(
    productId: String = "game.paseo",
    pinned: [PocketCardEntry] = [],
    stored: [PocketCardEntry] = [],
    repository: InMemoryPocketCardRepository? = nil
) async -> ProductPocketHostBridge {
    let held = repository ?? InMemoryPocketCardRepository()
    for card in stored {
        await held.insert(card, face: .nil)
    }
    let bridge = ProductPocketHostBridge(
        productId: productId,
        collection: RealPocketCardStore(pinned: InMemoryPinnedCards(pinned), repository: held)
    )
    await bridge.refresh()
    return bridge
}

/// Records what the bridge asked to republish, without asserting on a mock.
private final class Published: @unchecked Sendable {
    private(set) var counts: [Int] = []

    func record(_ cards: [PocketCard]) {
        counts.append(cards.count)
    }
}
