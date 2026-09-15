import Foundation
import Products

struct GameResultsDependencies {
    let groupRosterService: GameGroupRosterProviding
    let prizeService: AirdropPrizeServicing
    let memberService: GameMemberServicing
    let claimService: AirdropClaimServicing
    let nftsSubscriptionService: GameNftsSubscriptionServicing
    let personDataStore: DetermineStatePersonDataStore
    let usernameStorage: UsernameStoring
    let airdropRegistrationStore: AirdropRegistrationStoring
    let spaFlowState: SPAFlowState
}
