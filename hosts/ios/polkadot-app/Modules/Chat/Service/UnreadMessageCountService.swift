import CoreData
import Foundation
import Operation_iOS
import StructuredConcurrency

/// Counts incoming-new badge messages without materializing chat or message model graphs.
///
/// This service is used by the notification extension, where work happens during a short-lived
/// push-processing window. The fetch reads only `groupingId` and `messageId` columns via a
/// dictionary result type to avoid faulting the full message graph through
/// `ChatModelMapper.nonReactionUnreadCount`.
///
/// The count mirrors the app display badge semantics:
/// - incoming `.new` messages are counted.
/// - only messages attached to a chat are considered.
/// - reaction update messages are excluded from the badge count.
/// - system messages are excluded from the badge count.
/// - rows sharing a `groupingId` collapse to a single entry, so e.g. one call (offer + answer +
///   closed) increments the badge by 1.
final class UnreadMessageCountService {
    private let databaseService: CoreDataServiceProtocol

    init(
        databaseService: CoreDataServiceProtocol = UserDataStorageFacade.shared.databaseService
    ) {
        self.databaseService = databaseService
    }

    func totalUnreadBadgeMessageCount() async throws -> Int {
        try await databaseService.perform { context in
            let request = NSFetchRequest<NSDictionary>()
            request.entity = CDChatMessage.entity()
            request.predicate = Self.badgeCountPredicate()
            request.resultType = .dictionaryResultType
            request.returnsDistinctResults = true
            request.propertiesToFetch = [
                #keyPath(CDChatMessage.groupingId)
            ]
            let rows = try context.fetch(request)
            return rows.count
        }
    }
}

private extension UnreadMessageCountService {
    // Keep this aligned with `Chat.LocalMessage.Content.ContentType.isReaction` and `.isSystem`.
    static let badgeExcludedContentTypes = [
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.reacted.rawValue)),
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.reactionRemoved.rawValue)),
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.token.rawValue)),
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.deviceAdded.rawValue)),
        NSNumber(value: Int16(Chat.LocalMessage.Content.ContentType.deviceRemoved.rawValue))
    ]
}

extension UnreadMessageCountService {
    static func badgeCountPredicate() -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            .byStatus(.incoming(.new)),
            NSPredicate(format: "%K != nil", #keyPath(CDChatMessage.chat)),
            NSPredicate(format: "NOT (%K IN %@)", #keyPath(CDChatMessage.contentType), badgeExcludedContentTypes)
        ])
    }
}
