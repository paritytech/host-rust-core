import Foundation
import Operation_iOS
import CoreData

protocol PrivacyVoucherRepositoryMaking {
    var databaseService: CoreDataServiceProtocol { get }

    func createLocalVoucherRepository(
        forFilter filter: NSPredicate?
    ) -> AnyDataProviderRepository<LocalPrivacyVoucher>
}

final class PrivacyVoucherRepositoryFactory: PrivacyVoucherRepositoryMaking {
    private let storageFacade: StorageFacadeProtocol

    init(storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared) {
        self.storageFacade = storageFacade
    }

    var databaseService: CoreDataServiceProtocol { storageFacade.databaseService }

    func createLocalVoucherRepository(
        forFilter filter: NSPredicate?
    ) -> AnyDataProviderRepository<LocalPrivacyVoucher> {
        AnyDataProviderRepository(storageFacade.createRepository(
            filter: filter,
            sortDescriptors: [.localPrivacyVouchersByType, .localPrivacyVouchersByIndex],
            mapper: AnyCoreDataMapper(LocalPrivacyVoucherMapper())
        ))
    }
}
