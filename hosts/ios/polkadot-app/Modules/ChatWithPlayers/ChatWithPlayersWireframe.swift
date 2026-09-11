import Foundation
import SubstrateSdk

@MainActor
final class ChatWithPlayersWireframe: ChatWithPlayersWireframeProtocol {
    let flowState: ChatFlowState

    init(flowState: ChatFlowState) {
        self.flowState = flowState
    }

    func showChat(
        from view: ChatWithPlayersViewProtocol?,
        for accountId: AccountId
    ) {
        let chatId = Chat.Id.person(accountId)
        guard let chat = ChatViewFactory.createChatView(with: .existingChat(chatId), flowState: flowState) else {
            return
        }

        view?.controller.navigationController?.pushViewController(chat.controller, animated: true)
    }
}
