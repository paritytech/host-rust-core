import Foundation
import SubstrateSdk
import Individuality

struct GameContextSnapshot: Equatable {
    let maxGroupSize: UInt
    let playerCount: UInt
}

struct ReportSuccessContext {
    let gameIndex: GamePallet.GameIndex
    let player: GamePallet.AccountOrPerson
    let reportBlockHash: Data?
    let wasPersonBeforeReport: Bool
    let gameSnapshot: GameContextSnapshot
    let claimBeneficiary: AccountId
    let claimUsesScoreAlias: Bool
}
