import Foundation
import Individuality

struct GameHistory: Equatable {
    let items: [Item]
    let blockHash: Data?
}

extension GameHistory {
    struct Item: Equatable {
        let status: Status
        let date: Date
        let index: GamePallet.GameIndex
    }

    enum Status {
        case pending
        case waitingForResult
        case success
        case failure
    }
}
