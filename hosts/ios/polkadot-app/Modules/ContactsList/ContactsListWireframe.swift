import Foundation
import UIKit

@MainActor
final class ContactsListWireframe {
    let flowState: ChatFlowState

    init(flowState: ChatFlowState) {
        self.flowState = flowState
    }
}

private extension ContactsListWireframe {
    func performChatShow(from view: ContactsListViewProtocol?, for model: ChatOpenModel) {
        guard let chat = ChatViewFactory.createChatView(with: model, flowState: flowState) else {
            return
        }

        view?.controller.navigationController?.pushViewController(chat.controller, animated: true)
    }
}

extension ContactsListWireframe: ContactsListWireframeProtocol {
    func showSearchContact(from view: ContactsListViewProtocol?) {
        let searchModel = SearchContactModel { [weak self] openModel in
            self?.performChatShow(from: view, for: openModel)
        }

        guard let search = SearchContactViewFactory.createView(
            with: searchModel,
            coinageService: flowState.coinageService
        ) else {
            return
        }
        search.controller.modalPresentationStyle = .fullScreen
        search.controller.modalTransitionStyle = .crossDissolve
        view?.controller.present(search.controller, animated: true)
    }

    func showChat(from view: ContactsListViewProtocol?, for model: ChatOpenModel) {
        performChatShow(from: view, for: model)
    }

    func open(url: URL) {
        UIApplication.shared.open(url)
    }

    func showIncomingRequests(from view: ContactsListViewProtocol?) {
        guard let chatRequestList = ChatRequestListViewFactory.createView(for: flowState) else {
            return
        }

        chatRequestList.controller.hidesBottomBarWhenPushed = true

        view?.controller.navigationController?.pushViewController(
            chatRequestList.controller,
            animated: true
        )
    }
}
