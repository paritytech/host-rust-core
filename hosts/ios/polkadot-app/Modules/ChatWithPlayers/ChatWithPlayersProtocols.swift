import Foundation
import PolkadotUI
import SubstrateSdk
import UIKitExt

enum ChatWithPlayersError: Error {
    case contactNotFound
    case noAccountOrPerson
}

protocol ChatWithPlayersViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: [Player])
}

@MainActor
protocol ChatWithPlayersPresenterProtocol: AnyObject {
    func setup()
    func didSelectPlayer(_ player: Player)
}

protocol ChatWithPlayersInteractorInputProtocol: AnyObject {
    func setup()
    func addContact(for account: AccountId, username: String, imageData: Data?)
    func cancelContactRequest()
}

@MainActor
protocol ChatWithPlayersInteractorOutputProtocol: AnyObject {
    func didReceive(players: [GameVote])
    func didReceive(contacts: [Chat.Contact])
    func didReceive(remoteContact: Chat.RemoteContact)
    func didReceive(error: Error)
}

@MainActor
protocol ChatWithPlayersWireframeProtocol: AlertPresentable, ErrorPresentable {
    func showChat(from view: ChatWithPlayersViewProtocol?, for accountId: AccountId)
}
