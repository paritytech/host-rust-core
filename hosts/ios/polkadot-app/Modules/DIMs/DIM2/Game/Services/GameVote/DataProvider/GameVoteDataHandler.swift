import Foundation
import Operation_iOS

protocol GameVoteDataHandling {
    func handleGameVotes(result: Result<[DataProviderChange<GameVote>], Error>)
}
