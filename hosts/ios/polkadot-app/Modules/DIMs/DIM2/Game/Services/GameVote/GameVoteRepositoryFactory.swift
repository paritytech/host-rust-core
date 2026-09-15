import Foundation
import Operation_iOS
import CoreData

protocol GameVoteRepositoryMaking {
    var databaseService: CoreDataServiceProtocol { get }

    func createRepository(
        forFilter filter: NSPredicate?
    ) -> AnyDataProviderRepository<GameVote>
}

final class GameVoteRepositoryFactory: GameVoteRepositoryMaking {
    private let storageFacade: StorageFacadeProtocol

    init(storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared) {
        self.storageFacade = storageFacade
    }

    var databaseService: CoreDataServiceProtocol {
        storageFacade.databaseService
    }

    func createRepository(
        forFilter filter: NSPredicate?
    ) -> AnyDataProviderRepository<GameVote> {
        AnyDataProviderRepository(storageFacade.createRepository(
            filter: filter,
            sortDescriptors: [.gameVoteByUpdateDate],
            mapper: AnyCoreDataMapper(GameVoteMapper())
        ))
    }
}

extension GameVoteRepositoryMaking {
    func repository(forGame index: UInt32) -> AnyDataProviderRepository<GameVote> {
        createRepository(forFilter: .votes(forGame: index))
    }

    func repository(forAccount accountId: Data) -> AnyDataProviderRepository<GameVote> {
        createRepository(forFilter: .votes(forAccount: accountId))
    }
}

private extension NSPredicate {
    static func votes(forGame index: UInt32) -> NSPredicate {
        NSPredicate(format: "%K == %@", #keyPath(CDGameVote.gameIndex), "\(index)")
    }

    static func votes(forAccount accountId: Data) -> NSPredicate {
        NSPredicate(format: "%K == %@", #keyPath(CDGameVote.accountId), "\(accountId.toHex())")
    }
}
