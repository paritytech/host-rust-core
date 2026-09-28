import Foundation

final class WalletMainInteractor {
    weak var presenter: WalletMainInteractorOutputProtocol?

    private let collectiblesURLProvider: CollectiblesURLProviding
    private let networkStatusObserver: NetworkStatusObserving
    private let pocketPrewarmer: PocketPrewarmer
    private let pocket: PocketFacade
    private let cardHosts: PocketCardHosts
    private var resolutionTask: Task<Void, Never>?
    private var pocketTask: Task<Void, Never>?
    private var warming: Task<Void, Never>?

    init(
        collectiblesURLProvider: CollectiblesURLProviding,
        networkStatusObserver: NetworkStatusObserving,
        pocketPrewarmer: PocketPrewarmer,
        pocket: PocketFacade = .shared,
        cardHosts: PocketCardHosts = .shared
    ) {
        self.collectiblesURLProvider = collectiblesURLProvider
        self.networkStatusObserver = networkStatusObserver
        self.pocketPrewarmer = pocketPrewarmer
        self.pocket = pocket
        self.cardHosts = cardHosts
    }

    deinit {
        resolutionTask?.cancel()
        pocketTask?.cancel()
        warming?.cancel()
    }
}

extension WalletMainInteractor: WalletMainInteractorInputProtocol {
    func setup() {
        guard resolutionTask == nil else { return }

        networkStatusObserver.start { [weak self] status in
            self?.presenter?.didReceive(networkStatus: status)
        }

        #if FEATURE_DIMS
            resolutionTask = Task { [weak self, collectiblesURLProvider] in
                let url = await collectiblesURLProvider.resolveURL()

                guard !Task.isCancelled else { return }

                await self?.presenter?.didReceiveCollectibles(url: url)
            }
        #endif

        followPocket()
    }

    /// Removal is the store's, not the tab's: the collection is followed, so
    /// the card leaves the screen when it leaves storage rather than because
    /// this said so.
    func removePocketCard(_ card: PocketCardViewModel) {
        Task { [pocket] in
            guard let store = await pocket.store() else { return }

            _ = try? await store.removeCard(card.key)
        }
    }
}

private extension WalletMainInteractor {
    /// The collection is followed from storage, so the tab shows what the host
    /// holds without waiting on any product's worker, and shows every change
    /// whoever made it, the core removing a card included.
    func followPocket() {
        pocketTask = Task { [weak self, pocket] in
            guard let store = await pocket.store() else { return }

            do {
                for try await cards in store.observeCards() {
                    guard let self else { return }

                    await show(cards, from: store)
                }
            } catch {
                Logger.shared.error("[pocket] the wallet tab stopped following the collection: \(error)")
            }
        }
    }

    func show(_ cards: [PocketCardEntry], from store: any PocketCardStore) async {
        let drawn = await PocketCardsProvider(store: store).cards(cards)
        let held = Set(drawn.map(\.key))

        await MainActor.run { [cardHosts] in
            presenter?.didReceive(pocketCards: drawn)
            cardHosts.keepOnly { held.contains($0) }
        }

        prewarm(drawn)
    }

    /// Warming fetches an archive, so it runs beside the collection rather than
    /// in front of the next change: held here, every change that landed while
    /// it ran would arrive late, and the tab would sit on a stale collection.
    func prewarm(_ cards: [PocketCardViewModel]) {
        warming?.cancel()
        warming = Task { [pocketPrewarmer] in
            await pocketPrewarmer.warm(cards)
        }
    }
}
