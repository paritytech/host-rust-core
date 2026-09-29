import Foundation

final class CollectiblesInteractor {
    weak var presenter: CollectiblesInteractorOutputProtocol?

    private let bridge: CollectiblesBridge
    private let collectionService: CollectiblesCollectionServicing
    private let usernameStorage: UsernameStoring
    private let logger: LoggerProtocol

    private var loadTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?

    init(
        bridge: CollectiblesBridge,
        collectionService: CollectiblesCollectionServicing,
        usernameStorage: UsernameStoring = UsernameStorage(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.bridge = bridge
        self.collectionService = collectionService
        self.usernameStorage = usernameStorage
        self.logger = logger
    }

    deinit {
        loadTask?.cancel()
        eventsTask?.cancel()
    }
}

extension CollectiblesInteractor: CollectiblesInteractorInputProtocol {
    func setup() {
        observeBridgeEvents()
        loadCollection()
    }
}

private extension CollectiblesInteractor {
    func loadCollection() {
        loadTask?.cancel()
        let displayName = usernameStorage.username?.value
        loadTask = Task { [weak self, collectionService] in
            let owned = await collectionService.loadOwnedNfts()

            guard !Task.isCancelled else { return }

            let input = CollectionInput(owned: owned, displayName: displayName)
            await self?.presenter?.didReceive(collection: input)
        }
    }

    func observeBridgeEvents() {
        eventsTask?.cancel()
        eventsTask = Task { [weak self, bridge, logger] in
            for await event in bridge.events {
                guard let self else { return }
                await handle(event, logger: logger)
            }
        }
    }

    @MainActor
    func handle(_ event: CollectiblesInboundEvent, logger: LoggerProtocol) {
        switch event {
        case .ready:
            logger.debug("[Collectibles] flow.ready")
        case let .galleryShown(count):
            logger.debug("[Collectibles] flow.gallery_shown count=\(count)")
        case let .itemOpened(hash):
            logger.debug("[Collectibles] flow.item_opened hash=\(hash)")
        case let .itemClosed(hash):
            logger.debug("[Collectibles] flow.item_closed hash=\(hash)")
        case let .error(phase, detail):
            logger.error("[Collectibles] flow.error phase=\(phase) detail=\(detail ?? "nil")")
        case .close:
            logger.debug("[Collectibles] flow.close")
            presenter?.didRequestClose()
        case let .log(level, message):
            logger.debug("[Collectibles][JS] \(level ?? "log"): \(message)")
        }
    }
}
