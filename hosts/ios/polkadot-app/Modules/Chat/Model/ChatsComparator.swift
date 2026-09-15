import Foundation

enum ChatsComparator {
    static func lastMessageComparator(
        chat1: Chat.LocalModel,
        chat2: Chat.LocalModel
    ) -> Bool {
        guard let message1 = chat1.message, let message2 = chat2.message else {
            return chat1.message != nil ? true : false
        }

        guard message1.timestamp != message2.timestamp else {
            return chat1.identifier.localizedCompare(chat2.identifier) == .orderedAscending
        }

        return message1.timestamp >= message2.timestamp
    }

    static func lastMessageAndPinnedComparator(
        chat1: Chat.LocalModel,
        chat2: Chat.LocalModel
    ) -> Bool {
        let isPinned1 = chat1.peer.isPinnedToTop
        let isPinned2 = chat2.peer.isPinnedToTop

        guard isPinned1 == isPinned2 else {
            return isPinned1
        }

        return lastMessageComparator(chat1: chat1, chat2: chat2)
    }
}

extension Chat.Peer {
    var isPinnedToTop: Bool {
        if case let .chatExtension(extensionId, _) = self {
            return extensionId == DIM2ChatExtension.identifier
        }
        return false
    }
}
