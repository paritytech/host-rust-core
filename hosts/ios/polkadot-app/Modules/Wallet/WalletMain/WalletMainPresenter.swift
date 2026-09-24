import Foundation
import ChainRegistry

@MainActor
final class WalletMainPresenter {
    weak var view: WalletMainViewProtocol?
    let wireframe: WalletMainWireframeProtocol
    let interactor: WalletMainInteractorInputProtocol
    let titleViewModelFactory: NetworkStatusTitleViewModelMaking

    private var collectiblesURL: URL?
    private let pocketPrewarmer: PocketPrewarmer
    private let pocket: PocketFacade
    private var warming: Task<Void, Never>?

    init(
        interactor: WalletMainInteractorInputProtocol,
        wireframe: WalletMainWireframeProtocol,
        titleViewModelFactory: NetworkStatusTitleViewModelMaking,
        pocketPrewarmer: PocketPrewarmer,
        pocket: PocketFacade = .shared
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.titleViewModelFactory = titleViewModelFactory
        self.pocketPrewarmer = pocketPrewarmer
        self.pocket = pocket
    }
}

extension WalletMainPresenter: WalletMainPresenterProtocol {
    func setup() {
        didReceive(networkStatus: .connected)
        interactor.setup()
        loadPocketCards()
    }

    /// The collection is read from what the host already holds, so the cards
    /// are on screen without waiting on any product's worker, and again
    /// whenever one enters or leaves it.
    private func loadPocketCards() {
        Task { @MainActor in
            // Listening starts before the first read, which waits on a chain
            // read for the network's dotNS suffix: a card that entered the
            // collection in that window is announced once and by nobody again.
            var changes = pocket.changes().makeAsyncIterator()

            await showPocketCards()
            while await (try? changes.next()) != nil {
                await showPocketCards()
            }
        }
    }

    private func showPocketCards() async {
        guard let store = await pocket.store() else { return }

        let cards = await PocketCardsProvider(store: store).cards()
        view?.didReceive(pocketCards: cards)

        let held = Set(cards.map(\.key))
        PocketCardHosts.shared.keepOnly { held.contains($0) }
        prewarm(cards)
    }

    /// Warming fetches an archive, so it runs beside the collection rather than
    /// in front of the next change: held here, every change that landed while
    /// it ran would arrive late, and the tab would sit on a stale collection.
    private func prewarm(_ cards: [PocketCardViewModel]) {
        warming?.cancel()
        warming = Task { @MainActor [pocketPrewarmer] in
            await pocketPrewarmer.warm(cards)
        }
    }

    func showCollectibles() {
        guard let collectiblesURL else { return }
        wireframe.showCollectibles(from: view, url: collectiblesURL)
    }

    func showPocketCard(_ card: PocketCardViewModel) {
        wireframe.showPocketCard(card)
    }

    /// Confirmed first: a long press is easy to make by accident, and the card
    /// cannot be put back without the product offering it again.
    func removePocketCard(_ card: PocketCardViewModel) {
        wireframe.confirmPocketCardRemoval(card) { [weak self] in
            self?.remove(card)
        }
    }

    private func remove(_ card: PocketCardViewModel) {
        Task { @MainActor in
            guard let store = await pocket.store() else { return }

            _ = try? await store.removeCard(card.key)
            pocket.collectionChanged()
        }
    }
}

extension WalletMainPresenter: WalletMainInteractorOutputProtocol {
    func didReceiveCollectibles(url: URL?) {
        collectiblesURL = url
        view?.didReceive(isCollectiblesAvailable: url != nil)
    }

    func didReceive(networkStatus: NetworkStatus) {
        let titleViewModel = titleViewModelFactory.createTitleViewModel(for: networkStatus)
        view?.didReceive(titleViewModel: titleViewModel)
    }
}
