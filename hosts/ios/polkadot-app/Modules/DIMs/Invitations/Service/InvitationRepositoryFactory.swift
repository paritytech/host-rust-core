import Foundation
import Operation_iOS
import CoreData
import BigInt

protocol InvitationRepositoryFactoryProtocol {
    var databaseService: CoreDataServiceProtocol { get }

    func createInvitationRepository(filter: NSPredicate?) -> AnyDataProviderRepository<Invitation>
}

extension InvitationRepositoryFactoryProtocol {
    func createInvitationRepository() -> AnyDataProviderRepository<Invitation> {
        createInvitationRepository(filter: nil)
    }
}

final class InvitationRepositoryFactory: InvitationRepositoryFactoryProtocol {
    private let storageFacade: StorageFacadeProtocol

    init(storageFacade: StorageFacadeProtocol = SubstrateDataStorageFacade.shared) {
        self.storageFacade = storageFacade
    }

    var databaseService: CoreDataServiceProtocol { storageFacade.databaseService }

    func createInvitationRepository(filter: NSPredicate?) -> AnyDataProviderRepository<Invitation> {
        let repository = storageFacade.createRepository(
            filter: filter,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(InvitationMapper())
        )

        return AnyDataProviderRepository(repository)
    }
}
