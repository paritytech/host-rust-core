import Foundation

struct GameResultsInput: Encodable {
    let attestations: Attestations
    let member: MemberState
    let prizeDraw: PrizeDraw?
    let usernameClaim: UsernameClaim
    var onPrizeClaim: (() -> Void)?
    var attestationHashes: [String] = []

    private enum CodingKeys: String, CodingKey {
        case attestations
        case member
        case prizeDraw
        case usernameClaim
    }

    struct Attestations: Encodable {
        let score: Int?
        let total: Int
        let passed: Bool?
    }

    struct MemberState: Encodable, Equatable {
        let justBecameMember: Bool
        let displayName: String?
        let memberSince: String?

        private enum CodingKeys: String, CodingKey {
            case justBecameMember
            case displayName
            case memberSince
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(justBecameMember, forKey: .justBecameMember)
            try container.encodeIfPresent(displayName, forKey: .displayName)
            try container.encodeIfPresent(memberSince, forKey: .memberSince)
        }
    }

    struct PrizeDraw: Encodable {
        let prizeUsd: Decimal
        let userTicket: String
        let winningTickets: [String]
        let ticketDistance: Int
        let totalEntries: Int
        let nextDrawAt: String
        let won: Bool
    }

    struct UsernameClaim: Encodable, Equatable {
        let eligible: Bool
        let suggestedUsername: String?
        let previousUsername: String?
        let availability: Availability?
        let alternatives: [String]?

        enum Availability: String, Encodable, Equatable {
            case available
            case taken
            case unknown
        }
    }
}

/// The pass-gated game outcome, delivered via `window.setGameOutcome(...)` once attendance +
/// personhood resolve — separate from `setGameResults` because none of it is knowable upfront
/// (the attestations ARE the result and stream in over time). The webview accepts it late and
/// overrides, so the chest + reveal animations absorb the resolution latency.
struct GameOutcome: Encodable {
    let passed: Bool
    let justBecameMember: Bool
    let prizeDraw: GameResultsInput.PrizeDraw?
    let usernameClaim: GameResultsInput.UsernameClaim
}
