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

    init(
        interactor: WalletMainInteractorInputProtocol,
        wireframe: WalletMainWireframeProtocol,
        titleViewModelFactory: NetworkStatusTitleViewModelMaking,
        pocketPrewarmer: PocketPrewarmer
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.titleViewModelFactory = titleViewModelFactory
        self.pocketPrewarmer = pocketPrewarmer
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
            await showPocketCards()

            for try await _ in PocketFacade.shared.changes() {
                await showPocketCards()
            }
        }
    }

    private func showPocketCards() async {
        guard let store = await PocketFacade.shared.store() else { return }

        let cards = await PocketCardsProvider(store: store).cards()
        view?.didReceive(pocketCards: cards)

        // After the cards are on screen: warming is for the press that may
        // come, and must not hold up the collection the user is looking at.
        await pocketPrewarmer.warm(cards)
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
            guard let store = await PocketFacade.shared.store() else { return }

            _ = try? await store.removeCard(card.key)
            PocketFacade.shared.collectionChanged()
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
