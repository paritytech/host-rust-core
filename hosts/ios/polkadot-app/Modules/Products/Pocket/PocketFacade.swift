import Foundation
import AsyncExtensions
import Products
import TrUAPIHost

/// The one Pocket the process holds.
///
/// Built once and shared, because every surface reads the same collection: the
/// Wallet tab draws it, the approval sheet adds to it, and the core is served
/// one slice of it per product. Two collections would let a card appear in one
/// and not the other.
///
/// The build waits on the network's dotNS suffix — the reserved product a
/// host-placed card sits on is named per network, which can take a chain read —
/// so it is done on first use rather than at launch.
actor PocketFacade {
    static let shared = PocketFacade(tld: { try? await DotNsTldProviderFacade.shared.resolveTld() })

    private let tld: @Sendable () async -> String?
    private let repository: any PocketCardRepository
    private let changeSubject = AsyncPassthroughSubject<Void>()
    private var built: RealPocketCardStore?

    init(
        tld: @escaping @Sendable () async -> String?,
        repository: any PocketCardRepository = CoreDataPocketCardRepository()
    ) {
        self.tld = tld
        self.repository = repository
    }

    /// Nil only while the network is unknown, which is also when there is no
    /// reserved product for a host-placed card to sit on.
    func store() async -> (any PocketCardStore)? {
        if let built { return built }
        guard let tld = await tld() else { return nil }

        let store = RealPocketCardStore(pinned: AssetPinnedPocketCards(tld: tld), repository: repository)
        built = store
        return store
    }

    /// Fires whenever a card enters or leaves the collection, so every surface
    /// showing it re-reads. Faces are not announced here: they change at frame
    /// rate, and each card subscribes to its own.
    nonisolated func changes() -> AnyAsyncSequence<Void> {
        changeSubject.eraseToAnyAsyncSequence()
    }

    nonisolated func collectionChanged() {
        changeSubject.send(())
    }
}
