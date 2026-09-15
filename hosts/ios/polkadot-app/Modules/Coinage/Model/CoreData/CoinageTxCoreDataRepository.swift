import AsyncExtensions
import Coinage
import CoreData
import Foundation
import Operation_iOS

/// CoreData-backed ``CoinageTxRepositoryProtocol`` — the consolidation of the former
/// `DurabilityCoreDataStore` (public API) and `CoinageTransactionContext` (the atomic
/// read-validate-write transaction) into one repository.
///
/// Entries are never deleted: `minter(of:)` and `consumers(of:)` must still see terminal rows,
/// because a coin's provenance is what makes its absence mean anything. Handoff marks live on
/// `CDCoin.handoffMark` (insert-only) for the same reason.
///
/// Registration invariants are enforced in one store transaction, so a rejected registration
/// leaves nothing behind. Validation completes before any mutation, and the shared serial
/// `databaseService` queue serialises concurrent registrations. The read side of that transaction
/// is ``CoinageTxValidationContext``, built from the transaction's context; the write side is the
/// private context helpers below.
final class CoinageTxCoreDataRepository: CoinageTxRepositoryProtocol, @unchecked Sendable {
    private let repository: AnyDataProviderRepository<CoinageTxEntry>
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let storageFacade: StorageFacadeProtocol
    private let databaseService: CoreDataServiceProtocol
    private let entryMapper = CoinageTxEntryMapper()

    init(storageFacade: StorageFacadeProtocol) {
        self.storageFacade = storageFacade
        databaseService = storageFacade.databaseService

        let entryRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDCoinageTxEntry.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(CoinageTxEntryMapper())
        )
        repository = AnyDataProviderRepository(entryRepository)

        let coins = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(CoinMapper())
        )
        coinRepository = AnyDataProviderRepository(coins)
    }
}

// MARK: - Registration

extension CoinageTxCoreDataRepository {
    func register(
        _ registrations: [CoinageTxRegistration],
        validation: @escaping (any CoinageTxValidationContextProtocol) throws -> Void,
        onCommit: @escaping ([CoinageTxId]) -> Void
    ) async throws {
        guard !registrations.isEmpty else { return }
        try await withTransaction { context in
            // The batch is validated once, before any insert — the validation closure rejects
            // within-batch conflicts itself, since these rows do not exist yet.
            try validation(CoinageTxValidationContext(context: context))

            var ids: [CoinageTxId] = []
            for registration in registrations {
                let entry = try registration.makeEntry(id: CoinageTxId(), sequence: self.nextSequence(in: context))
                try self.upsert(entry, in: context)
                ids.append(entry.id)
            }

            // Inside the transaction, before the rows are visible: the caller takes ownership so a
            // pass can never reach a committed entry before the watcher does.
            onCommit(ids)
        }
    }
}

// MARK: - Status writes

extension CoinageTxCoreDataRepository {
    @discardableResult
    func updateTxStatus(
        for id: CoinageTxId,
        expectedCurrentStatus: CoinageTxStatus,
        verdict: Verdict
    ) async throws -> Bool {
        try await withTransaction { context in
            guard let entry = try self.entry(id, in: context) else { return false }
            guard entry.status.isLive, entry.status == expectedCurrentStatus else { return false }

            // Skip a write that changes nothing — a verdict restating the current status and record.
            guard entry.status != verdict.status || entry.successDetectedAt != verdict.successDetectedAt else {
                return false
            }

            let updated = entry.withStatus(verdict.status).withSuccessDetectedAt(verdict.successDetectedAt)
            try self.upsert(updated, in: context)
            return true
        }
    }
}

// MARK: - Reads

extension CoinageTxCoreDataRepository {
    func getAllEntries() async throws -> [CoinageTxEntry] {
        try await repository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func getEntry(id: CoinageTxId) async throws -> CoinageTxEntry? {
        let operation = repository.fetchOperation(by: { id.uuidString }, options: RepositoryFetchOptions())
        return try await operation.asyncExecute()
    }

    func subscribeStatus(id: CoinageTxId) -> AnyAsyncSequence<CoinageTxStatus> {
        storageFacade.subscribeSingle(
            mapper: AnyCoreDataMapper(CoinageTxEntryMapper()),
            filter: NSPredicate(format: "%K == %@", #keyPath(CDCoinageTxEntry.identifier), id.uuidString)
        )
        .compactMap { $0?.status }
        .eraseToAnyAsyncSequence()
    }

    func getOperationGroupStatuses(_ groupId: CoinageTxGroupId) async throws -> [CoinageTxEntry] {
        let groupRepository = storageFacade.createRepository(
            filter: NSPredicate(format: "%K == %@", #keyPath(CDCoinageTxEntry.groupId), groupId),
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDCoinageTxEntry.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(CoinageTxEntryMapper())
        )
        return try await AnyDataProviderRepository(groupRepository)
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func subscribeOperationGroupStatuses(_ groupId: CoinageTxGroupId) -> AnyAsyncSequence<[CoinageTxEntry]> {
        storageFacade.subscribeSnapshot(
            mapper: AnyCoreDataMapper(CoinageTxEntryMapper()),
            filter: NSPredicate(format: "%K == %@", #keyPath(CDCoinageTxEntry.groupId), groupId),
            transform: { $0.sorted { $0.sequence < $1.sequence } }
        )
    }

    func minter(of asset: OwnAsset) async throws -> CoinageTxEntry? {
        let key = asset.publicKey
        return try await getAllEntries().first { entry in
            entry.outputs.contains { $0.publicKey == key }
        }
    }

    func consumers(of input: CoinageTxInput) async throws -> [CoinageTxEntry] {
        let key = input.publicKey
        return try await getAllEntries().filter { entry in
            entry.inputs.contains { $0.publicKey == key }
        }
    }
}

// MARK: - Handoff marks

extension CoinageTxCoreDataRepository {
    func precommitHandOff(
        _ assets: [OwnAsset],
        validation: @escaping (any CoinageTxValidationContextProtocol) throws -> Void
    ) async throws {
        guard !assets.isEmpty else { return }
        try await withTransaction { context in
            try validation(CoinageTxValidationContext(context: context))
            for asset in assets {
                try self.markHandoffPending(asset, in: context)
            }
        }
    }

    func commitHandoffs(_ keys: [PublicKey]) async throws {
        guard !keys.isEmpty else { return }
        try await withTransaction { context in
            for key in keys {
                try self.commitHandoff(key: key, in: context)
            }
        }
    }

    func releaseUncommittedHandoffs() async throws {
        try await withTransaction { try self.releaseUncommittedMarks(in: $0) }
    }

    func handedOffCoins() async throws -> [OwnAsset] {
        try await handedOffCoinModels().map { .coin($0.derivationIndex, $0.publicKey) }
    }

    /// The handoff mark is stored on `CDCoin`, so a non-`.none` `handoffMark` identifies a
    /// handed-off coin. The mark is insert-only, so this never mistakes a released coin for one.
    private func handedOffCoinModels() async throws -> [Coin] {
        try await coinRepository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .filter { $0.handoffMark != .none }
    }
}

// MARK: - Transaction

private extension CoinageTxCoreDataRepository {
    /// Executes a transaction block within the shared CoreData context, saving on success and
    /// rolling back on error, so a rejected registration leaves nothing behind.
    ///
    /// WARNING: Do not call `withTransaction` from within another `withTransaction` body — that
    /// would deadlock on the shared serial dispatch queue. The callers above never nest.
    ///
    /// Invariant: `context.save()` commits whatever is pending on the shared context. This holds
    /// today because every `CoreDataRepository` write saves-or-rolls-back within its own `perform`
    /// block, but this is a convention and is unenforced app-wide.
    func withTransaction<T>(_ body: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await databaseService.perform { context in
            do {
                let result = try body(context)
                try context.save()
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}

// MARK: - Context write helpers

private extension CoinageTxCoreDataRepository {
    func nextSequence(in context: NSManagedObjectContext) throws -> Int64 {
        let request = NSFetchRequest<CDCoinageTxEntry>(entityName: "CDCoinageTxEntry")
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(CDCoinageTxEntry.sequence), ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false

        let entities = try context.fetch(request)
        return (entities.first?.sequence ?? 0) + 1
    }

    /// Re-populates the existing row or inserts a fresh one. The mapper leaves the immutable
    /// inputs/outputs alone on an update.
    func upsert(_ entry: CoinageTxEntry, in context: NSManagedObjectContext) throws {
        let existing: CDCoinageTxEntry? = try context.first(
            for: NSPredicate(format: "%K == %@", #keyPath(CDCoinageTxEntry.identifier), entry.identifier)
        )
        let entity = try existing ?? context.insertNew(CDCoinageTxEntry.self)
        try entryMapper.populate(entity: entity, from: entry, using: context)
    }

    func entry(_ id: CoinageTxId, in context: NSManagedObjectContext) throws -> CoinageTxEntry? {
        guard let entity: CDCoinageTxEntry = try context.first(
            for: NSPredicate(format: "%K == %@", #keyPath(CDCoinageTxEntry.identifier), id.uuidString)
        ) else { return nil }
        return try entryMapper.transform(entity: entity)
    }

    func markHandoffPending(_ asset: OwnAsset, in context: NSManagedObjectContext) throws {
        guard let coin = try coinForAsset(asset, in: context) else { return }
        // Never regress a committed mark back to provisional.
        if coin.handoffMark == CoinHandoffMark.none.rawValue {
            coin.handoffMark = CoinHandoffMark.pending.rawValue
        }
    }

    func commitHandoff(key: PublicKey, in context: NSManagedObjectContext) throws {
        let coin: CDCoin? = try context.first(for: NSPredicate(format: "publicKey == %@", key.toHex()))
        coin?.handoffMark = CoinHandoffMark.committed.rawValue
    }

    func releaseUncommittedMarks(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<CDCoin>(entityName: "CDCoin")
        request.predicate = NSPredicate(
            format: "handoffMark == %d", Int(CoinHandoffMark.pending.rawValue)
        )
        for coin in try context.fetch(request) {
            coin.handoffMark = CoinHandoffMark.none.rawValue
        }
    }

    func coinForAsset(_ asset: OwnAsset, in context: NSManagedObjectContext) throws -> CDCoin? {
        guard case let .coin(index, _) = asset else { return nil }
        return try context.first(for: NSPredicate(format: "identifier == %@", Coin.identifier(for: index)))
    }
}
