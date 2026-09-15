import Operation_iOS
import Foundation

protocol PrivacyVoucherDataProviderMaking {
    func createLocalVoucherProvider() -> StreamableProvider<LocalPrivacyVoucher>
}

final class PrivacyVoucherDataProviderFactory {
    let repositoryFactory: PrivacyVoucherRepositoryMaking
    let operationQueue: OperationQueue
    let logger: LoggerProtocol

    init(
        repositoryFactory: PrivacyVoucherRepositoryMaking = PrivacyVoucherRepositoryFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.repositoryFactory = repositoryFactory
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension PrivacyVoucherDataProviderFactory: PrivacyVoucherDataProviderMaking {
    func createLocalVoucherProvider() -> StreamableProvider<LocalPrivacyVoucher> {
        let repository = repositoryFactory.createLocalVoucherRepository(forFilter: nil)
        let source = EmptyStreamableSource<LocalPrivacyVoucher>()
        let mapper = LocalPrivacyVoucherMapper()

        let repositoryObservable = CoreDataContextObservable(
            service: repositoryFactory.databaseService,
            mapper: AnyCoreDataMapper(mapper),
            predicate: { _ in true }
        )

        repositoryObservable.start { [weak self] error in
            if let error {
                self?.logger.error("Did receive error: \(error)")
            }
        }

        return StreamableProvider(
            source: AnyStreamableSource(source),
            repository: repository,
            observable: AnyDataProviderRepositoryObservable(repositoryObservable),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}
