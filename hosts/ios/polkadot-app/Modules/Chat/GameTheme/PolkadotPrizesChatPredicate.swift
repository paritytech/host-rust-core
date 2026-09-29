import Foundation

enum PolkadotPrizesChatPredicate {
    static func isPolkadotPrizes(_ chatId: Chat.Id) -> Bool {
        if case let .chatExtension(extId, _) = chatId, extId == DIM2ChatExtension.identifier {
            return true
        }
        return false
    }
}
