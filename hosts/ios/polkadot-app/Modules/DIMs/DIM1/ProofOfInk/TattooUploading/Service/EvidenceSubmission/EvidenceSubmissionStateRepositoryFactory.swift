import Foundation
import Operation_iOS

protocol EvidenceStateRepositoryFactoryProtocol {
    var databaseService: CoreDataServiceProtocol { get }

    func createLocalStateRepository() -> AnyDataProviderRepository<EvidenceSubmission.LocalState>

    func createSessionRepository(
        for sessionId: String?
    ) -> AnyDataProviderRepository<EvidenceSubmission.Session>
}

final class EvidenceStateRepositoryFactory {
    let substrateFacade: StorageFacadeProtocol

    init(substrateFacade: StorageFacadeProtocol) {
        self.substrateFacade = substrateFacade
    }
}

extension EvidenceStateRepositoryFactory: EvidenceStateRepositoryFactoryProtocol {
    var databaseService: CoreDataServiceProtocol {
        substrateFacade.databaseService
    }

    func createLocalStateRepository() -> AnyDataProviderRepository<EvidenceSubmission.LocalState> {
        let mapper = SingleValueMapper<EvidenceSubmission.LocalState>()

        let filter = NSPredicate(
            format: "%K == %@",
            #keyPath(CDSingleValue.identifier),
            EvidenceSubmission.LocalState.identifier
        )
        let repository = substrateFacade.createRepository(
            filter: filter,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )

        return AnyDataProviderRepository(repository)
    }

    func createSessionRepository(
        for sessionId: String?
    ) -> AnyDataProviderRepository<EvidenceSubmission.Session> {
        let mapper = SingleValueMapper<EvidenceSubmission.Session>()

        let filter: NSPredicate? =
            if let sessionId {
                NSPredicate(
                    format: "%K == %@",
                    #keyPath(CDSingleValue.identifier),
                    sessionId
                )
            } else {
                nil
            }

        let repository = substrateFacade.createRepository(
            filter: filter,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )

        return AnyDataProviderRepository(repository)
    }
}
