import AsyncExtensions
import Coinage
import CoreData
import DurableTransactions
import Foundation
import Operation_iOS

/// CoreData-backed ``CoinageAssetLedgerProtocol``: coinage's input/output rows on the engine's
/// `CDDurableTx`, and the handoff marks on `CDCoin`.
///
/// Registration writes only inside the engine's transaction, through the ``CoreDataRegistrationScope``
/// it is handed: the invariants run against that same context, so nothing they check can move before
/// both halves commit, and a rejection rolls the engine's row back with them. Handoff marks are a
/// separate insert-only record on `CDCoin.handoffMark` whose presence survives any later state change.
final class CoinageAssetLedgerCoreData: CoinageAssetLedgerProtocol, @unchecked Sendable {
    private let storageFacade: StorageFacadeProtocol
    private let databaseService: CoreDataServiceProtocol
    private let entries: AnyDataProviderRepository<CoinageTxEntry>
    private let coins: AnyDataProviderRepository<Coin>
    private let validator = CoinageTxRegistrationValidator()

    init(storageFacade: StorageFacadeProtocol) {
        self.storageFacade = storageFacade
        databaseService = storageFacade.databaseService

        let entryRepository = storageFacade.createRepository(
            filter: Self.domainPredicate,
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurableTx.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(CoinageTxEntryMapper())
        )
        entries = AnyDataProviderRepository(entryRepository)

        let coinRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(CoinMapper())
        )
        coins = AnyDataProviderRepository(coinRepository)
    }

    private static let domainPredicate = NSPredicate(
        format: "%K == %@", #keyPath(CDDurableTx.domainId), TxDomainId.coinage.rawValue
    )
}

// MARK: - Registration

extension CoinageAssetLedgerCoreData {
    func registerAssets(
        _ registrations: [CoinageAssetRegistration],
        for ids: [CoinageTxId],
        in scope: any DurableTxRegistrationScope
    ) throws {
        guard let scope = scope as? CoreDataRegistrationScope else {
            throw DurableTxError.foreignRegistrationScope
        }
        let context = scope.context

        // The batch is validated once, before any row is written — the validator rejects within-batch
        // conflicts itself, since these rows do not exist yet.
        try validator.validate(registrations, transaction: CoinageTxValidationContext(context: context))

        for (id, registration) in zip(ids, registrations) {
            guard let entity: CDDurableTx = try context.first(
                for: NSPredicate(format: "%K == %@", #keyPath(CDDurableTx.identifier), id.uuidString)
            ) else {
                throw CoinageTxError.entryNotFound(id)
            }
            try CoinageTxAssetRows.populate(
                entity: entity,
                inputs: registration.inputs,
                outputs: registration.outputs,
                using: context
            )
            CoinageTxAssetRows.touchRelatedAssets(of: entity)
        }
    }
}

// MARK: - Reads

extension CoinageAssetLedgerCoreData {
    func getAllEntries() async throws -> [CoinageTxEntry] {
        try await entries
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func getEntry(id: CoinageTxId) async throws -> CoinageTxEntry? {
        try await entries
            .fetchOperation(by: { id.uuidString }, options: RepositoryFetchOptions())
            .asyncExecute()
    }

    func getOperationGroupStatuses(_ groupId: CoinageTxGroupId) async throws -> [CoinageTxEntry] {
        let groupRepository = storageFacade.createRepository(
            filter: Self.groupPredicate(groupId),
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurableTx.sequence), ascending: true)],
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
            filter: Self.groupPredicate(groupId),
            transform: { $0.sorted { $0.sequence < $1.sequence } }
        )
    }

    private static func groupPredicate(_ groupId: CoinageTxGroupId) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            domainPredicate,
            NSPredicate(format: "%K == %@", #keyPath(CDDurableTx.groupId), groupId)
        ])
    }
}

// MARK: - Handoff marks

extension CoinageAssetLedgerCoreData {
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

    /// The handoff mark is stored on `CDCoin`, so a non-`.none` `handoffMark` identifies a handed-off
    /// coin. The mark is insert-only, so this never mistakes a released coin for one.
    private func handedOffCoinModels() async throws -> [Coin] {
        try await coins
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .filter { $0.handoffMark != .none }
    }
}

// MARK: - Transaction

private extension CoinageAssetLedgerCoreData {
    /// A transaction of coinage's own, for the handoff writes. Never opened while the engine's
    /// registration transaction is running: `registerAssets` writes through the scope it is handed and
    /// must not call this — nesting would deadlock on the shared serial dispatch queue.
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

private extension CoinageAssetLedgerCoreData {
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
