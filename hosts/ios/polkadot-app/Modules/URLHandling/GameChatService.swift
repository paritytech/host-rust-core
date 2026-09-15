import Foundation
import UIKit

final class GameChatService {
    let host = "players"

    let flowState: ChatFlowState
    init(flowState: ChatFlowState) {
        self.flowState = flowState
    }
}

extension GameChatService: URLHandlingServiceProtocol {
    func handle(url: URL) -> Bool {
        guard url.host() == host else {
            return false
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let queryItems = components.queryItems,
            let gameId = queryItems.first(where: { $0.name == "id" })?.value,
            let gameDateString = queryItems.first(where: { $0.name == "date" })?.value
        else {
            return false
        }

        guard
            let date = try? Date(gameDateString, strategy: .iso8601),
            let game = UInt32(gameId)
        else {
            return false
        }

        Task { @MainActor in
            guard
                let view = ChatWithPlayersViewFactory.createView(
                    game: game,
                    gameDate: date,
                    chatFlowState: flowState
                )?.controller
            else {
                return
            }

            let topVC = UIWindow.topWindow?.topmostViewController
            let navigationController = topVC?.navigationController
            assert(navigationController != nil)
            navigationController?.pushViewController(view, animated: true)
        }
        return true
    }
}
