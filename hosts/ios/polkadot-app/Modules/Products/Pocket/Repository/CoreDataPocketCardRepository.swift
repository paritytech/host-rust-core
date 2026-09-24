import Foundation
import Operation_iOS
import Products
import TrUAPIHost

/// Cards the user added, and the newest face held for any card, kept across
/// launches.
///
/// Nothing here throws to its caller. This is read by the Wallet tab, by the
/// card list the core asks for and by the deeplink handler, none of which have
/// anywhere to put a storage failure: a card that cannot be read is one the
/// Pocket does without until the next launch, where a throw would take the
/// whole tab down.
final class CoreDataPocketCardRepository: PocketCardRepository, @unchecked Sendable {
    private let cardRepository: AnyDataProviderRepository<StoredPocketCard>
    private let faceRepository: AnyDataProviderRepository<StoredPocketCardFace>
    private let decoder = RendererNodeJsonDecoder()
    private let encoder = RendererNodeJsonEncoder()
    private let logger: LoggerProtocol

    init(
        storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        cardRepository = AnyDataProviderRepository(
            storageFacade.createRepository(mapper: AnyCoreDataMapper(PocketCardMapper()))
        )
        faceRepository = AnyDataProviderRepository(
            storageFacade.createRepository(mapper: AnyCoreDataMapper(PocketCardFaceMapper()))
        )
        self.logger = logger
    }

    /// Oldest first, so the Pocket keeps the order cards were added in rather
    /// than whatever order the store happens to return them.
    func cards() async -> [PocketCardEntry] {
        do {
            return try await cardRepository.fetchAllOperation(with: .init())
                .asyncExecute()
                .sorted { $0.addedAt < $1.addedAt }
                .map { PocketCardEntry(key: $0.key, title: $0.title, privileged: false) }
        } catch {
            logger.error("pocket: the stored cards could not be read: \(error)")
            return []
        }
    }

    func insert(_ card: PocketCardEntry, face: RendererNode) async {
        let stored = StoredPocketCard(key: card.key, title: card.title, addedAt: Date())

        do {
            try await cardRepository.saveOperation({ [stored] }, { [] }).asyncExecute()
        } catch {
            logger.error("pocket: '\(card.key.storageId)' could not be stored: \(error)")
        }

        await saveFace(face, for: card.key)
    }

    /// The face goes with the card: a card added again must not inherit the
    /// face the last one was approved by.
    func delete(_ key: PocketCardKey) async -> Bool {
        let held = await cards().contains { $0.key == key }

        do {
            try await cardRepository.saveOperation({ [] }, { [key.storageId] }).asyncExecute()
            try await faceRepository.saveOperation({ [] }, { [key.storageId] }).asyncExecute()
        } catch {
            logger.error("pocket: '\(key.storageId)' could not be removed: \(error)")
            return false
        }

        return held
    }

    /// A face the running app can no longer read is answered as none: the card
    /// keeps its place and waits for its product to draw again.
    func face(for key: PocketCardKey) async -> RendererNode? {
        do {
            guard let stored = try await faceRepository
                .fetchOperation(by: { key.storageId }, options: .init())
                .asyncExecute()
            else {
                return nil
            }

            return try decoder.decode(stored.faceJson)
        } catch {
            logger.warning("pocket: the kept face for '\(key.storageId)' no longer reads: \(error)")
            return nil
        }
    }

    func saveFace(_ face: RendererNode, for key: PocketCardKey) async {
        do {
            let stored = try StoredPocketCardFace(key: key, faceJson: encoder.encode(face))
            try await faceRepository.saveOperation({ [stored] }, { [] }).asyncExecute()
        } catch {
            logger.warning("pocket: the newest face for '\(key.storageId)' could not be kept: \(error)")
        }
    }
}
