import Foundation

struct GameSchedule: Equatable {
    let items: [Item]
}

extension GameSchedule {
    struct Item: Equatable {
        let registrationStartDate: Date
        let registrationEndDate: Date
        let gameStartDate: Date
        let requiredScoreOverride: Int?
    }
}
