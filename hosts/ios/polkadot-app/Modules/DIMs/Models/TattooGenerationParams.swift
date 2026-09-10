import Foundation
import Individuality
import SubstrateSdk

struct TattooGenerationParams {
    let personalId: ProofOfInkPallet.PersonalId
    let accountId: AccountId
    let entropy: Data?
}
