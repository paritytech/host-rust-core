import AsyncExtensions
import CoreData
import DurableTransactions
import Foundation
import Operation_iOS

/// CoreData-backed ``DurableTxRepositoryProtocol``: the engine's ledger row, domain-neutral.
///
/// Registration opens the one write transaction; a domain's store writes its own rows inside it through
/// ``CoreDataRegistrationScope``, so both halves commit or roll back together. The shared serial
/// `databaseService` queue serialises concurrent registrations, which is what makes a domain's invariant
/// checks inside the hook sound. Entries are never deleted.
final class DurableTxCoreDataRepository: DurableTxRepositoryProtocol, @unchecked Sendable {
    private let repository: AnyDataProviderRepository<DurableTxEntry>
    private let storageFacade: StorageFacadeProtocol
    private let databaseService: CoreDataServiceProtocol
    private let rowObservers: [any DurableTxRowObserving]
    private let mapper = DurableTxMapper()

    init(storageFacade: StorageFacadeProtocol, rowObservers: [any DurableTxRowObserving] = []) {
        self.storageFacade = storageFacade
        self.rowObservers = rowObservers
        databaseService = storageFacade.databaseService

        let entryRepository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurableTx.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(DurableTxMapper())
        )
        repository = AnyDataProviderRepository(entryRepository)
    }
}

// MARK: - Registration

extension DurableTxCoreDataRepository {
    func register(
        _ registrations: [DurableTxRegistration],
        onRegister: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        guard !registrations.isEmpty else { return [] }
        return try await withTransaction { context in
            var ids: [DurableTxId] = []
            for registration in registrations {
                let entry = try registration.makeEntry(id: DurableTxId(), sequence: self.nextSequence(in: context))
                try self.insert(entry, in: context)
                ids.append(entry.id)
            }

            // Inside the transaction, before the rows are visible: the domain writes its rows and the
            // caller takes ownership, so a pass can never reach a committed entry before its watcher.
            try onRegister(CoreDataRegistrationScope(context: context), ids)
            return ids
        }
    }
}

// MARK: - Status writes

extension DurableTxCoreDataRepository {
    @discardableResult
    func updateTxStatus(
        for id: DurableTxId,
        expectedCurrentStatus: DurableTxStatus,
        verdict: Verdict
    ) async throws -> Bool {
        try await withTransaction { context in
            guard let entity = try self.entity(id, in: context) else { return false }
            let current = try self.mapper.transform(entity: entity)
            guard current.status.isLive, current.status == expectedCurrentStatus else { return false }

            // Skip a write that changes nothing — a verdict restating the current status and record.
            guard current.status != verdict.status || current.successDetectedAt != verdict.successDetectedAt else {
                return false
            }

            DurableTxMapper.apply(status: verdict.status, successDetectedAt: verdict.successDetectedAt, to: entity)
            for observer in self.rowObservers {
                observer.didChangeStatus(of: entity, in: context)
            }
            return true
        }
    }
}

// MARK: - Reads

extension DurableTxCoreDataRepository {
    func getAllEntries() async throws -> [DurableTxEntry] {
        try await repository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func getAllEntries(domain: TxDomainId) async throws -> [DurableTxEntry] {
        let domainRepository = storageFacade.createRepository(
            filter: NSPredicate(format: "%K == %@", #keyPath(CDDurableTx.domainId), domain.rawValue),
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurableTx.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(DurableTxMapper())
        )
        return try await AnyDataProviderRepository(domainRepository)
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func getEntry(id: DurableTxId) async throws -> DurableTxEntry? {
        try await repository
            .fetchOperation(by: { id.uuidString }, options: RepositoryFetchOptions())
            .asyncExecute()
    }

    func subscribeStatus(id: DurableTxId) -> AnyAsyncSequence<DurableTxStatus> {
        storageFacade.subscribeSingle(
            mapper: AnyCoreDataMapper(DurableTxMapper()),
            filter: NSPredicate(format: "%K == %@", #keyPath(CDDurableTx.identifier), id.uuidString)
        )
        .compactMap { $0?.status }
        .eraseToAnyAsyncSequence()
    }

    func getGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) async throws -> [DurableTxEntry] {
        let groupRepository = storageFacade.createRepository(
            filter: Self.groupPredicate(domain: domain, groupId: groupId),
            sortDescriptors: [NSSortDescriptor(key: #keyPath(CDDurableTx.sequence), ascending: true)],
            mapper: AnyCoreDataMapper(DurableTxMapper())
        )
        return try await AnyDataProviderRepository(groupRepository)
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
            .sorted { $0.sequence < $1.sequence }
    }

    func subscribeGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) -> AnyAsyncSequence<[DurableTxEntry]> {
        storageFacade.subscribeSnapshot(
            mapper: AnyCoreDataMapper(DurableTxMapper()),
            filter: Self.groupPredicate(domain: domain, groupId: groupId),
            transform: { $0.sorted { $0.sequence < $1.sequence } }
        )
    }

    private static func groupPredicate(domain: TxDomainId, groupId: DurableTxGroupId) -> NSPredicate {
        NSPredicate(
            format: "%K == %@ AND %K == %@",
            #keyPath(CDDurableTx.domainId),
            domain.rawValue,
            #keyPath(CDDurableTx.groupId),
            groupId
        )
    }
}

// MARK: - Transaction

private extension DurableTxCoreDataRepository {
    /// Executes a transaction block within the shared CoreData context, saving on success and rolling
    /// back on error, so a rejected registration leaves nothing behind — in either store.
    ///
    /// WARNING: Do not call `withTransaction` from within another `withTransaction` body — that would
    /// deadlock on the shared serial dispatch queue. A domain store handed the registration scope writes
    /// through the scope's context and never opens a transaction of its own.
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

// MARK: - Context helpers

private extension DurableTxCoreDataRepository {
    func nextSequence(in context: NSManagedObjectContext) throws -> Int64 {
        let request = NSFetchRequest<CDDurableTx>(entityName: "CDDurableTx")
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(CDDurableTx.sequence), ascending: false)]
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false

        let entities = try context.fetch(request)
        return (entities.first?.sequence ?? 0) + 1
    }

    func insert(_ entry: DurableTxEntry, in context: NSManagedObjectContext) throws {
        let entity = try context.insertNew(CDDurableTx.self)
        try mapper.populate(entity: entity, from: entry, using: context)
    }

    func entity(_ id: DurableTxId, in context: NSManagedObjectContext) throws -> CDDurableTx? {
        try context.first(
            for: NSPredicate(format: "%K == %@", #keyPath(CDDurableTx.identifier), id.uuidString)
        )
    }
}
