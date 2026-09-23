import Foundation
import TrUAPIHost

/// The settled collection: the cards the host placed, then the ones the user
/// added, each with the newest face held for it.
struct RealPocketCardStore: PocketCardStore {
    private let pinned: any PinnedPocketCards
    private let repository: any PocketCardRepository

    init(pinned: any PinnedPocketCards, repository: any PocketCardRepository) {
        self.pinned = pinned
        self.repository = repository
    }

    /// Pinned cards keep the front, and a card the user added before the host
    /// came to pin it is listed once, as the pinned one — the stored copy is
    /// not privileged, so listing it too would offer a permanent card for
    /// removal.
    func cards() async -> [PocketCardEntry] {
        let placed = await pinned.cards()
        let placedKeys = Set(placed.map(\.key))
        let added = await repository.cards().filter { !placedKeys.contains($0.key) }

        return placed + added
    }

    func removeCard(_ key: PocketCardKey) async throws -> PocketRemoval {
        guard pinned.pinned(key) == nil else { throw PocketRemoveError.privileged }

        return await repository.delete(key) ? .removed : .absent
    }

    func add(_ card: PocketCardEntry, face: RendererNode) async {
        await repository.insert(card, face: face)
    }

    /// A host-placed card falls back to the face shipped with the app, so it
    /// draws on first run and again after its product stops drawing.
    func face(for key: PocketCardKey) async -> RendererNode? {
        if let kept = await repository.face(for: key) { return kept }
        guard pinned.pinned(key) != nil else { return nil }

        return await pinned.face(for: key.cardId)
    }

    func cacheFace(_ face: RendererNode, for key: PocketCardKey) async {
        await repository.saveFace(face, for: key)
    }
}
