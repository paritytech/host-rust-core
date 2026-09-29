import Foundation
import Operation_iOS
import Individuality

protocol GameVoteDataProviderMaking {
    func createVisibleVotesProvider(
        for gameIndex: GamePallet.GameIndex
    ) -> StreamableProvider<GameVote>
}

final class GameVoteDataProviderFactory {
    private let repositoryFactory: GameVoteRepositoryMaking
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    init(
        repositoryFactory: GameVoteRepositoryMaking = GameVoteRepositoryFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.repositoryFactory = repositoryFactory
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension GameVoteDataProviderFactory: GameVoteDataProviderMaking {
    func createVisibleVotesProvider(
        for gameIndex: GamePallet.GameIndex
    ) -> StreamableProvider<GameVote> {
        let repository = repositoryFactory.createRepository(
            forFilter: visibleVotesPredicate(for: gameIndex)
        )
        let source = EmptyStreamableSource<GameVote>()
        let mapper = GameVoteMapper()

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

private extension GameVoteDataProviderFactory {
    func visibleVotesPredicate(for gameIndex: GamePallet.GameIndex) -> NSPredicate {
        let gameIndexPredicate = NSPredicate(
            format: "%K == %i",
            #keyPath(CDGameVote.gameIndex),
            gameIndex
        )
        let notBannedPredicate = NSPredicate(
            format: "%K == NO",
            #keyPath(CDGameVote.isBanned)
        )
        let hasPreviewPredicate = NSPredicate(
            format: "%K != nil",
            #keyPath(CDGameVote.previewImageData)
        )
        return NSCompoundPredicate(
            type: .and,
            subpredicates: [
                gameIndexPredicate,
                notBannedPredicate,
                hasPreviewPredicate
            ]
        )
    }
}
