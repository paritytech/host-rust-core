import Foundation
import PolkadotUI
import SubstrateSdk

import UIKit.UIImage

@MainActor
final class ChatWithPlayersPresenter {
    weak var view: ChatWithPlayersViewProtocol?
    let wireframe: ChatWithPlayersWireframeProtocol
    let interactor: ChatWithPlayersInteractorInputProtocol
    let logger: LoggerProtocol

    private var votes: [GameVote] = []
    private var contacts: Set<AccountId> = []
    private var loadingPlayerId: String? {
        didSet {
            provideViewModel()
        }
    }

    private let usernameGenerator: UsernameGeneratorProtocol

    init(
        interactor: ChatWithPlayersInteractorInputProtocol,
        wireframe: ChatWithPlayersWireframeProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.logger = logger

        usernameGenerator = UsernameGenerator()
    }
}

extension ChatWithPlayersPresenter: ChatWithPlayersPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func didSelectPlayer(_ player: Player) {
        guard loadingPlayerId != player.id else {
            return
        }

        if player.isContact {
            openChat(player)
        } else {
            request(player)
        }
    }
}

extension ChatWithPlayersPresenter: ChatWithPlayersInteractorOutputProtocol {
    func didReceive(players: [GameVote]) {
        votes = players
        provideViewModel()
    }

    func didReceive(contacts: [Chat.Contact]) {
        self.contacts = Set(contacts.map(\.accountId))
        provideViewModel()
    }

    func didReceive(remoteContact: Chat.RemoteContact) {
        guard
            votes.contains(where: { $0.accountId == remoteContact.accountId })
        else {
            return
        }

        loadingPlayerId = nil
    }

    func didReceive(error: Error) {
        logger.error("Did receive error: \(error)")
        loadingPlayerId = nil

        _ = wireframe.present(error: error, from: view)
    }
}

private extension ChatWithPlayersPresenter {
    func provideViewModel() {
        let models = votes.map {
            let isContact = contacts.contains($0.accountId)

            return Player(
                id: $0.identifier,
                username: usernameGenerator.generate(from: $0.accountId),
                image: $0.previewImageData.flatMap { UIImage(data: $0) },
                isContact: isContact,
                isLoading: loadingPlayerId == $0.identifier
            )
        }
        view?.didReceive(viewModel: models)
    }

    func openChat(_ player: Player) {
        interactor.cancelContactRequest()
        loadingPlayerId = nil

        guard
            let vote = votes.first(where: { $0.identifier == player.id })
        else {
            return
        }

        wireframe.showChat(from: view, for: vote.accountId)
    }

    func request(_ player: Player) {
        guard
            let vote = votes.first(where: { $0.identifier == player.id })
        else {
            return
        }

        loadingPlayerId = player.id

        interactor.addContact(
            for: vote.accountId,
            username: player.username,
            imageData: vote.previewImageData
        )
    }
}
