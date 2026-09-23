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
        custody: NativeTransferCustody?,
        authorization: (@Sendable () throws -> Void)?,
        in scope: any DurableTxRegistrationScope
    ) throws {
        guard let scope = scope as? CoreDataRegistrationScope else {
            throw DurableTxError.foreignRegistrationScope
        }
        let context = scope.context
        guard registrations.count == ids.count else { throw NativeTransferCustodyError.invalidRecord }
        if let custody {
            guard try nativeRecord(custodyId: custody.custodyId, in: context) == nil else {
                throw NativeTransferCustodyError.alreadyRegistered
            }
            guard let authorization else { throw NativeTransferCustodyError.invalidRecord }
            try authorization()
            try custody.validate(
                registrations: registrations, transaction: CoinageTxValidationContext(context: context)
            )
        }

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
        if let custody {
            try retain(custody, registrations: registrations, ids: ids, in: context)
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

// MARK: - Native custody

extension CoinageAssetLedgerCoreData {
    func retainNativeTransfer(
        _ custody: NativeTransferCustody, authorization: @escaping @Sendable () throws -> Void
    ) async throws {
        try await withTransaction { context in
            guard try self.nativeRecord(custodyId: custody.custodyId, in: context) == nil else {
                throw NativeTransferCustodyError.alreadyRegistered
            }
            try authorization()
            try custody.validate(registrations: [], transaction: CoinageTxValidationContext(context: context))
            try self.retain(custody, registrations: [], ids: [], in: context)
        }
    }

    func retainedNativeTransfer(custodyId: String) async throws -> NativeTransferCustody? {
        try await databaseService.perform { context in
            guard let record = try self.nativeRecord(custodyId: custodyId, in: context) else { return nil }
            guard let data = record.value(forKey: "payload") as? Data else {
                throw NativeTransferCustodyError.incompleteRegistration
            }
            let saved = try JSONDecoder().decode(NativeCustodyRecord.self, from: data)
            guard saved.custody.custodyId == custodyId, !saved.custody.entries.isEmpty else {
                throw NativeTransferCustodyError.incompleteRegistration
            }
            for entry in saved.custody.entries {
                let coin = try self.retainedCoin(entry, in: context)
                guard coin.handoffMark == CoinHandoffMark.committed.rawValue else {
                    throw NativeTransferCustodyError.incompleteRegistration
                }
            }
            for transaction in saved.transactions {
                guard let row: CDDurableTx = try context.first(
                    for: NSPredicate(format: "identifier == %@", transaction.id.uuidString)
                ), row.domainId == TxDomainId.coinage.rawValue else {
                    throw NativeTransferCustodyError.incompleteRegistration
                }
                let inputs = try CoinageTxAssetRows.transformInputs(from: row.inputs).map(\.publicKey)
                let outputs = try CoinageTxAssetRows.transformOutputs(from: row.outputs).map(\.publicKey)
                guard inputs.count == transaction.inputs.count, Set(inputs) == Set(transaction.inputs),
                      outputs.count == transaction.outputs.count, Set(outputs) == Set(transaction.outputs) else {
                    throw NativeTransferCustodyError.incompleteRegistration
                }
            }
            return saved.custody
        }
    }
}

private extension CoinageAssetLedgerCoreData {
    struct NativeCustodyRecord: Codable {
        struct Transaction: Codable {
            let id: CoinageTxId
            let inputs: [Data]
            let outputs: [Data]
        }

        let custody: NativeTransferCustody
        let transactions: [Transaction]
    }

    func nativeRecord(custodyId: String, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDNativeCoinageRecord")
        request.predicate = NSPredicate(format: "identifier == %@", "coinage.native.custody." + custodyId)
        request.fetchLimit = 2
        let rows = try context.fetch(request)
        guard rows.count <= 1 else { throw NativeTransferCustodyError.incompleteRegistration }
        return rows.first
    }

    func retainedCoin(_ entry: NativeTransferCustody.Entry, in context: NSManagedObjectContext) throws -> CDCoin {
        guard let coin: CDCoin = try context.first(
            for: NSPredicate(format: "identifier == %@", Coin.identifier(for: entry.coinDerivationIndex))
        ), coin.publicKey == entry.publicKey.toHex(), coin.exponent == entry.valueExponent else {
            throw NativeTransferCustodyError.incompleteRegistration
        }
        return coin
    }

    /// Called only within the engine scope or the exact-match ledger transaction. No nested save.
    func retain(
        _ custody: NativeTransferCustody,
        registrations: [CoinageAssetRegistration],
        ids: [CoinageTxId],
        in context: NSManagedObjectContext
    ) throws {
        let saved = NativeCustodyRecord(
            custody: custody,
            transactions: zip(ids, registrations).map {
                NativeCustodyRecord.Transaction(
                    id: $0.0, inputs: $0.1.inputs.map(\.publicKey), outputs: $0.1.outputs.map(\.publicKey)
                )
            }
        )
        let data = try JSONEncoder().encode(saved)
        for entry in custody.entries {
            let coin = try retainedCoin(entry, in: context)
            coin.handoffMark = CoinHandoffMark.committed.rawValue
        }
        let record = NSEntityDescription.insertNewObject(forEntityName: "CDNativeCoinageRecord", into: context)
        record.setValue("coinage.native.custody." + custody.custodyId, forKey: "identifier")
        record.setValue(data, forKey: "payload")
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
