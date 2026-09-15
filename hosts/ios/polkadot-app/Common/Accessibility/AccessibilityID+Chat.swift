import ExternalAccessibility
import Foundation

extension AccessibilityID.Chats {
    static func chatListRow(_ chat: Chat.LocalModel) -> (any AccessibilityIdentifying)? {
        chat.chatId.extensionId == DIM2ChatExtension.identifier
            ? AccessibilityID.Game.polkadotPeerChat
            : chatRow
    }
}

extension AccessibilityID.Game {
    static func welcomeCard(text: String?) -> (any AccessibilityIdentifying)? {
        switch text {
        case String(localized: .WeeklyGame.welcome3),
             String(localized: .WeeklyGame.w3SWelcome3):
            gestureCard
        case String(localized: .WeeklyGame.w3SWelcome6):
            membershipCard
        default:
            nil
        }
    }
}
