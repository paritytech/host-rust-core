import Foundation
import BigInt

struct ScoreInfo: Equatable {
    let score: Int?
    let streak: Int?
    let requiredScore: Int
    let credit: BigUInt?
    let isParticipant: Bool
    let isRegistrableParticipant: Bool
    let isSuspended: Bool
    let isExternallyRecognized: Bool
}
