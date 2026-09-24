import Foundation
import Products
import Testing
import TrUAPIHost
@testable import polkadot_app

struct PocketCardStoreTests {
    // MARK: - Ordering

    /// Host-placed cards keep the front of the collection, so a product cannot
    /// push Humanity down the Pocket by adding its own.
    @Test
    func listsPinnedCardsBeforeAddedOnes() async throws {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([humanity]),
            repository: InMemoryPocketCardRepository([loyalty])
        )

        let cards = await store.cards()

        #expect(cards.map(\.key) == [humanity.key, loyalty.key])
    }

    /// A card the user added before the host came to pin it is listed once, as
    /// the pinned one, so it cannot be removed by the copy that is not pinned.
    @Test
    func listsACardHeldBothWaysOnlyOnce() async throws {
        let alsoStored = PocketCardEntry(key: humanity.key, title: "stale copy", privileged: false)
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([humanity]),
            repository: InMemoryPocketCardRepository([alsoStored, loyalty])
        )

        let cards = await store.cards()

        #expect(cards.map(\.key) == [humanity.key, loyalty.key])
        #expect(cards.first?.privileged == true)
        #expect(cards.first?.title == humanity.title)
    }

    // MARK: - Removal

    @Test
    func refusesToRemoveAPrivilegedCard() async {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([humanity]),
            repository: InMemoryPocketCardRepository([])
        )

        await #expect(throws: PocketRemoveError.privileged) {
            try await store.removeCard(humanity.key)
        }
    }

    /// The core asks a host to tell a removal it performed apart from one it
    /// had nothing to do, and both are successes.
    @Test
    func removingACardThatIsNotHeldSucceedsAsAbsent() async throws {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([]),
            repository: InMemoryPocketCardRepository([])
        )

        #expect(try await store.removeCard(loyalty.key) == .absent)
    }

    @Test
    func removingAHeldCardDropsIt() async throws {
        let repository = InMemoryPocketCardRepository([loyalty])
        let store = RealPocketCardStore(pinned: InMemoryPinnedCards([]), repository: repository)

        #expect(try await store.removeCard(loyalty.key) == .removed)

        let remaining = await store.cards()
        #expect(remaining.isEmpty)
    }

    // MARK: - Faces

    /// The approval sheet showed a face, and that is the face the Pocket draws:
    /// the card is stored with it rather than re-read from anywhere.
    @Test
    func keepsTheFaceACardWasAddedWith() async throws {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([]),
            repository: InMemoryPocketCardRepository()
        )

        await store.add(loyalty, face: .string(text: "approved"))

        #expect(await store.face(for: loyalty.key) == .string(text: "approved"))
    }

    /// A host-placed card draws on first run, before its product has ever run,
    /// from the face shipped with the app.
    @Test
    func fallsBackToTheBundledFaceForAPinnedCard() async throws {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([humanity], face: .string(text: "bundled")),
            repository: InMemoryPocketCardRepository()
        )

        #expect(await store.face(for: humanity.key) == .string(text: "bundled"))
    }

    /// Once its product draws, a pinned card keeps that face rather than the
    /// bundled one, so it is right at the next cold start too.
    @Test
    func prefersTheKeptFaceOverTheBundledOne() async throws {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([humanity], face: .string(text: "bundled")),
            repository: InMemoryPocketCardRepository()
        )

        await store.cacheFace(.string(text: "drawn"), for: humanity.key)

        #expect(await store.face(for: humanity.key) == .string(text: "drawn"))
    }

    /// A card nobody holds has no face to answer with, pinned or not.
    @Test
    func answersNoFaceForACardItDoesNotHold() async {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([], face: .string(text: "bundled")),
            repository: InMemoryPocketCardRepository()
        )

        #expect(await store.face(for: loyalty.key) == nil)
    }

    /// A card added again must be drawn by the face the user approved the
    /// second time, not the one left behind by the first.
    @Test
    func dropsTheFaceWhenTheCardIsRemoved() async throws {
        let store = RealPocketCardStore(
            pinned: InMemoryPinnedCards([]),
            repository: InMemoryPocketCardRepository()
        )
        await store.add(loyalty, face: .string(text: "approved"))

        _ = try await store.removeCard(loyalty.key)

        #expect(await store.face(for: loyalty.key) == nil)
    }
}

// MARK: - Fixtures

private let humanity = PocketCardEntry(
    key: PocketCardKey(productId: "peopl.paseo", cardId: PocketCardId(value: "humanity")),
    title: "Humanity",
    privileged: true
)

private let loyalty = PocketCardEntry(
    key: PocketCardKey(productId: "game.paseo", cardId: PocketCardId(value: "loyalty")),
    title: "Loyalty",
    privileged: false
)

// MARK: - In-memory doubles

actor InMemoryPocketCardRepository: PocketCardRepository {
    private var stored: [PocketCardEntry]
    private var faces: [PocketCardKey: RendererNode] = [:]

    init(_ stored: [PocketCardEntry] = []) {
        self.stored = stored
    }

    func cards() async -> [PocketCardEntry] { stored }

    func insert(_ card: PocketCardEntry, face: RendererNode) async {
        stored.removeAll { $0.key == card.key }
        stored.append(card)
        faces[card.key] = face
    }

    func delete(_ key: PocketCardKey) async -> Bool {
        let before = stored.count
        stored.removeAll { $0.key == key }
        faces[key] = nil
        return stored.count != before
    }

    func face(for key: PocketCardKey) async -> RendererNode? { faces[key] }

    func saveFace(_ face: RendererNode, for key: PocketCardKey) async { faces[key] = face }
}

struct InMemoryPinnedCards: PinnedPocketCards {
    private let cardsHeld: [PocketCardEntry]
    private let bundledFace: RendererNode?

    init(_ cardsHeld: [PocketCardEntry], face: RendererNode? = nil) {
        self.cardsHeld = cardsHeld
        bundledFace = face
    }

    func cards() async -> [PocketCardEntry] { cardsHeld }

    func pinned(_ key: PocketCardKey) -> PocketCardEntry? {
        cardsHeld.first { $0.key == key }
    }

    func face(for _: PocketCardId) async -> RendererNode? { bundledFace }
}
