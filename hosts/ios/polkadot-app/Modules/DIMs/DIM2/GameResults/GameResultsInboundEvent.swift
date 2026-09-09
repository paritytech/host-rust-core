import Foundation

// Web → native events
enum GameResultsInboundEvent {
    case ready
    case resultsShown
    case prizeDrawStarted
    case prizeDrawComplete(won: Bool)
    case nftRevealStarted(count: Int)
    case nftRevealComplete
    case usernameClaimRequested
    case requestDisplayName
    case usernameAvailabilityNeeded(name: String)
    case error(phase: String, detail: String?)
    case complete
    case log(level: String?, message: String)

    // swiftlint:disable:next cyclomatic_complexity
    static func decode(from body: Any) throws -> GameResultsInboundEvent? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Expected {type:String,...}")
            )
        }
        switch type {
        case "flow.ready":
            return .ready
        case "flow.results_shown":
            return .resultsShown
        case "flow.prize_draw_started":
            return .prizeDrawStarted
        case "flow.prize_draw_complete":
            let won = (dict["won"] as? Bool) ?? false
            return .prizeDrawComplete(won: won)
        case "flow.nft_reveal_started":
            let count = (dict["count"] as? Int) ?? 0
            return .nftRevealStarted(count: count)
        case "flow.nft_reveal_complete":
            return .nftRevealComplete
        case "flow.username_claim_requested":
            return .usernameClaimRequested
        case "flow.request_display_name":
            return .requestDisplayName
        case "flow.username_availability_needed":
            let name = (dict["name"] as? String) ?? ""
            return .usernameAvailabilityNeeded(name: name)
        case "flow.error":
            let phase = (dict["phase"] as? String) ?? "unknown"
            let detail = dict["detail"] as? String
            return .error(phase: phase, detail: detail)
        case "flow.complete":
            return .complete
        case "log":
            let level = dict["level"] as? String
            let message = (dict["message"] as? String) ?? String(describing: dict)
            return .log(level: level, message: message)
        default:
            return nil
        }
    }
}
