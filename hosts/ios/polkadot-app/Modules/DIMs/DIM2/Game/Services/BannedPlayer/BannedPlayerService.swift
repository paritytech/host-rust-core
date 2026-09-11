import Foundation
import Operation_iOS
import SubstrateSdk

protocol BannedPlayerServicing {
    func fetchAll() async throws -> Set<AccountId>
    func save(_ accountId: AccountId) async throws
    func delete(_ accountId: AccountId) async throws
}

final class BannedPlayerService {
    private let repository: AnyDataProviderRepository<BannedPlayer>

    init(storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared) {
        repository = AnyDataProviderRepository(storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(BannedPlayerMapper())
        ))
    }
}

extension BannedPlayerService: BannedPlayerServicing {
    func fetchAll() async throws -> Set<AccountId> {
        let operation = repository.fetchAllOperation(with: RepositoryFetchOptions())
        let items = try await operation.asyncExecute()
        return Set(items.map(\.accountId))
    }

    func save(_ accountId: AccountId) async throws {
        let player = BannedPlayer(accountId: accountId)
        let operation = repository.saveOperation({ [player] }, { [] })
        try await operation.asyncExecute()
    }

    func delete(_ accountId: AccountId) async throws {
        let identifier = accountId.toHex()
        let operation = repository.saveOperation({ [] }, { [identifier] })
        try await operation.asyncExecute()
    }
}
