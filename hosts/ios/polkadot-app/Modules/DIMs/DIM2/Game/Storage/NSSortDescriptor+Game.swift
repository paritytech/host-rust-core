import Foundation

extension NSSortDescriptor {
    static var gameVoteByUpdateDate: NSSortDescriptor {
        NSSortDescriptor(key: #keyPath(CDGameVote.voteUpdateDate), ascending: false)
    }
}
