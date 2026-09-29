import Foundation

enum PolkadotPrizesBubbleStyleResolver {
    static func style(for chatId: Chat.Id) -> InboxBubbleStyle? {
        guard PolkadotPrizesChatPredicate.isPolkadotPrizes(chatId) else { return nil }
        return InboxBubbleStyle(
            bubbleColor: PolkadotPrizesPalette.bubbleViolet,
            textColor: PolkadotPrizesPalette.bubbleText,
            strokeColor: PolkadotPrizesPalette.bubbleStroke,
            strokeWidth: PolkadotPrizesPalette.bubbleStrokeWidth
        )
    }
}
