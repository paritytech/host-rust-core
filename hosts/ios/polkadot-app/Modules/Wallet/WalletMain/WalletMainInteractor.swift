import Foundation

final class WalletMainInteractor {
    weak var presenter: WalletMainInteractorOutputProtocol?

    private let collectiblesURLProvider: CollectiblesURLProviding
    private let networkStatusObserver: NetworkStatusObserving
    private var resolutionTask: Task<Void, Never>?

    init(
        collectiblesURLProvider: CollectiblesURLProviding,
        networkStatusObserver: NetworkStatusObserving
    ) {
        self.collectiblesURLProvider = collectiblesURLProvider
        self.networkStatusObserver = networkStatusObserver
    }

    deinit {
        resolutionTask?.cancel()
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
    }
}
