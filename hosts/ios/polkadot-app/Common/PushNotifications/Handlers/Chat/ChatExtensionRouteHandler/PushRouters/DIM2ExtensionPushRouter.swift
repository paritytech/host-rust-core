import Foundation
import UIKit

final class DIM2ExtensionPushRouter: ChatExtensionPushRouting {
    func process(
        userInfo: [AnyHashable: Any],
        chatOpenClosure: (() -> Void)?
    ) {
        guard
            let gamePushTypeRaw = userInfo[PushNotificationKeys.gameState] as? Int,
            let gamePushType = PushGameNotificationType(rawValue: gamePushTypeRaw)
        else { return }

        switch gamePushType {
        case .waitingRoom,
             .start:
            let gameIndex = userInfo[PushNotificationKeys.gameIndex] as? Int
            let url = AppConfig.DeepLink.game(intendedGameIndex: gameIndex)
            UIApplication.shared.open(url)
        case .register:
            chatOpenClosure?()
        }
    }
}
