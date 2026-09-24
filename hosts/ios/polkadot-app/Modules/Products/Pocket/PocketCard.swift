import Foundation
import Products
import TrUAPIHost

/// Identifies one card: the product that backs it, and the label that product
/// declared for it.
struct PocketCardKey: Hashable {
    let productId: ProductId
    let cardId: PocketCardId

    /// Flat form the card is stored under, and the one CoreData keys rows by.
    var storageId: String { "\(productId)/\(cardId.value)" }

    /// Where the card's product opens: its own page, told which card the user
    /// came from. Built the same way on every host, so a product is handed the
    /// same address whichever one it is running on.
    var launchUrl: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = productId
        components.queryItems = [URLQueryItem(name: "card", value: cardId.value)]

        return components.url
    }
}

/// One card in the host's Pocket collection. A privileged card is host-placed
/// and removable by nobody.
struct PocketCardEntry: Equatable {
    let key: PocketCardKey
    let title: String
    let privileged: Bool
}

/// What a removal did. A privileged card is refused with
/// ``PocketRemoveError/privileged`` instead; removing a card that is not held
/// is a success, which the core asks a host to tell apart from one it performed.
enum PocketRemoval {
    case removed
    case absent
}

enum PocketRemoveError: Error, Equatable {
    case privileged
}

/// The host-owned collection as a product sees it. Cards enter only through the
/// host's own approval flow, so there is no add here.
protocol PocketCollection {
    func cards() async -> [PocketCardEntry]

    func removeCard(_ key: PocketCardKey) async throws -> PocketRemoval
}

/// The collection as the host's own flows see it: what a product may read, plus
/// the writes only the host makes.
protocol PocketCardStore: PocketCollection {
    /// Adds a card the user approved, together with the face they approved it by.
    func add(_ card: PocketCardEntry, face: RendererNode) async

    /// The newest face held for `key`: the last one its product drew, or the
    /// bundled one for a host-placed card that has never drawn.
    func face(for key: PocketCardKey) async -> RendererNode?

    /// Keeps the newest face a product drew, so the card has it offline and at
    /// cold start.
    func cacheFace(_ face: RendererNode, for key: PocketCardKey) async
}

/// Cards the user added, held across launches, and the newest face held for any
/// card. A host-placed card has no membership row, but its face is kept here
/// like every other.
protocol PocketCardRepository {
    func cards() async -> [PocketCardEntry]

    func insert(_ card: PocketCardEntry, face: RendererNode) async

    /// Whether a card was held under `key`.
    func delete(_ key: PocketCardKey) async -> Bool

    func face(for key: PocketCardKey) async -> RendererNode?

    func saveFace(_ face: RendererNode, for key: PocketCardKey) async
}

/// The cards the host itself places: present on first run, removable by nobody.
protocol PinnedPocketCards {
    func cards() async -> [PocketCardEntry]

    /// The host-placed card `key` names, if it names one. Answers without
    /// awaiting: a removal arrives from the core on a thread it cannot spare.
    func pinned(_ key: PocketCardKey) -> PocketCardEntry?

    /// The face shipped with the app for a host-placed card.
    func face(for cardId: PocketCardId) async -> RendererNode?
}
