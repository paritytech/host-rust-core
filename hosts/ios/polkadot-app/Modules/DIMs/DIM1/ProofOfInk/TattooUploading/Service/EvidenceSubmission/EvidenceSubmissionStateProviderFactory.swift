import Foundation
import Operation_iOS

protocol EvidenceLocalDataProviderFactoryProtocol {
    func createEvidenceSubmissionLocalState() -> StreamableProvider<EvidenceSubmission.LocalState>
    func createEvidenceSubmissionSession(
        for sessionId: String
    ) -> StreamableProvider<EvidenceSubmission.Session>
}

final class EvidenceLocalDataProviderFactory {
    let repositoryFactory: EvidenceStateRepositoryFactoryProtocol
    let operationQueue: OperationQueue
    let logger: LoggerProtocol

    init(
        repositoryFactory: EvidenceStateRepositoryFactoryProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.repositoryFactory = repositoryFactory
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension EvidenceLocalDataProviderFactory: EvidenceLocalDataProviderFactoryProtocol {
    func createEvidenceSubmissionLocalState() -> StreamableProvider<EvidenceSubmission.LocalState> {
        let repository = repositoryFactory.createLocalStateRepository()

        let source = EmptyStreamableSource<EvidenceSubmission.LocalState>()

        let mapper = SingleValueMapper<EvidenceSubmission.LocalState>()

        let repositoryObservable = CoreDataContextObservable(
            service: repositoryFactory.databaseService,
            mapper: AnyCoreDataMapper(mapper)
        ) { entity in
            entity.identifier == EvidenceSubmission.LocalState.identifier
        }

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

    func createEvidenceSubmissionSession(
        for sessionId: String
    ) -> StreamableProvider<EvidenceSubmission.Session> {
        let repository = repositoryFactory.createSessionRepository(for: sessionId)

        let source = EmptyStreamableSource<EvidenceSubmission.Session>()

        let mapper = SingleValueMapper<EvidenceSubmission.Session>()

        let repositoryObservable = CoreDataContextObservable(
            service: repositoryFactory.databaseService,
            mapper: AnyCoreDataMapper(mapper)
        ) { entity in
            entity.identifier == sessionId
        }

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
