import Foundation

// Web → native events
enum CollectiblesInboundEvent {
    case ready
    case galleryShown(count: Int)
    case itemOpened(hash: String)
    case itemClosed(hash: String)
    case error(phase: String, detail: String?)
    case close
    case log(level: String?, message: String)

    static func decode(from body: Any) throws -> CollectiblesInboundEvent? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Expected {type:String,...}")
            )
        }
        switch type {
        case "flow.ready":
            return .ready
        case "flow.gallery_shown":
            let count = (dict["count"] as? Int) ?? 0
            return .galleryShown(count: count)
        case "flow.item_opened":
            let hash = (dict["hash"] as? String) ?? ""
            return .itemOpened(hash: hash)
        case "flow.item_closed":
            let hash = (dict["hash"] as? String) ?? ""
            return .itemClosed(hash: hash)
        case "flow.error":
            let phase = (dict["phase"] as? String) ?? "unknown"
            let detail = dict["detail"] as? String
            return .error(phase: phase, detail: detail)
        case "flow.close":
            return .close
        case "log":
            let level = dict["level"] as? String
            let message = (dict["message"] as? String) ?? String(describing: dict)
            return .log(level: level, message: message)
        default:
            return nil
        }
    }
}
