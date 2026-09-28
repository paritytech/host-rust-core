import Foundation
import Operation_iOS
import Products
import TrUAPIHost

/// Cards the user added, and the newest face held for any card, kept across
/// launches.
///
/// Reads and removals raise what went wrong. The core tells a failure apart
/// from an empty Pocket and from a card that was already gone, and a product
/// told its removal succeeded when it did not will not ask again. Surfaces with
/// nowhere to put a failure, the Wallet tab first of all, fall back to an empty
/// list themselves.
///
/// Faces are the exception: one that no longer reads is answered as none, and
/// the card keeps its place and waits for its product to draw again.
final class CoreDataPocketCardRepository: PocketCardRepository, @unchecked Sendable {
    private let cardRepository: AnyDataProviderRepository<StoredPocketCard>
    private let faceRepository: AnyDataProviderRepository<StoredPocketCardFace>
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
    func cards() async throws -> [PocketCardEntry] {
        try await cardRepository.fetchAllOperation(with: .init())
            .asyncExecute()
            .sorted { $0.addedAt < $1.addedAt }
            .map { PocketCardEntry(key: $0.key, title: $0.title, privileged: false) }
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
    ///
    /// Looked up by id rather than over the whole collection, because this runs
    /// while the core waits on the answer.
    func delete(_ key: PocketCardKey) async throws -> Bool {
        let held = try await cardRepository
            .fetchOperation(by: { key.storageId }, options: .init())
            .asyncExecute() != nil

        try await cardRepository.saveOperation({ [] }, { [key.storageId] }).asyncExecute()
        try await faceRepository.saveOperation({ [] }, { [key.storageId] }).asyncExecute()

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

            return try decodeRendererNode(bytes: stored.face)
        } catch {
            logger.warning("pocket: the kept face for '\(key.storageId)' no longer reads: \(error)")
            return nil
        }
    }

    func saveFace(_ face: RendererNode, for key: PocketCardKey) async {
        do {
            let stored = StoredPocketCardFace(key: key, face: encodeRendererNode(node: face))
            try await faceRepository.saveOperation({ [stored] }, { [] }).asyncExecute()
        } catch {
            logger.warning("pocket: the newest face for '\(key.storageId)' could not be kept: \(error)")
        }
    }
}
