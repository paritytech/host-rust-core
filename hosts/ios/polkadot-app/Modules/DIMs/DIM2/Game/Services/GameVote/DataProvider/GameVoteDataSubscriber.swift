import Foundation
import Operation_iOS
import Individuality

protocol GameVoteDataSubscribing: LocalStorageProviderObserving where Self: AnyObject {
    var gameVoteDataHandler: GameVoteDataHandling { get }
    var gameVoteDataProviderFactory: GameVoteDataProviderMaking { get }

    func subscribeOnVisibleGameVotes(
        for gameIndex: GamePallet.GameIndex,
        on queue: DispatchQueue
    ) -> StreamableProvider<GameVote>
}

extension GameVoteDataSubscribing where Self: GameVoteDataHandling {
    var gameVoteDataHandler: GameVoteDataHandling { self }

    func subscribeOnVisibleGameVotes(
        for gameIndex: GamePallet.GameIndex,
        on queue: DispatchQueue
    ) -> StreamableProvider<GameVote> {
        let provider = gameVoteDataProviderFactory.createVisibleVotesProvider(
            for: gameIndex
        )

        addStreamableProviderObserver(
            for: provider,
            updateClosure: { [weak self] changes in
                self?.gameVoteDataHandler.handleGameVotes(
                    result: .success(changes)
                )
            },
            failureClosure: { [weak self] error in
                self?.gameVoteDataHandler.handleGameVotes(
                    result: .failure(error)
                )
            },
            callbackQueue: queue,
            options: .allNonblocking()
        )

        return provider
    }
}
