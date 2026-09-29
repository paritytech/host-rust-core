import Foundation
import Individuality

struct TattooCommitModel {
    let name: String
    let description: String
    let tattooSize: Int
    let tattooMaxSize: Int?
    let evidenceLowerTimeframe: OnChainHour?
    let evidenceUpperTimeframe: OnChainHour?
}
