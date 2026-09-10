import Foundation
import Observation
import UIKit.UIImage

public struct Player: Identifiable {
    public let id: String
    public let username: String
    public let image: UIImage?
    public let isContact: Bool
    public let isLoading: Bool

    public init(
        id: String,
        username: String,
        image: UIImage?,
        isContact: Bool,
        isLoading: Bool = false
    ) {
        self.id = id
        self.username = username
        self.image = image
        self.isContact = isContact
        self.isLoading = isLoading
    }
}

public protocol ChatWithPlayersViewModelProtocol: Observable {
    var players: [Player] { get set }
    var action: (Player) -> Void { get set }

    func didTapAction(for player: Player)
}

@Observable
public final class ChatWithPlayersViewModel: ChatWithPlayersViewModelProtocol {
    public var players: [Player] = []
    public var action: (Player) -> Void = { _ in }

    public init() {}

    public func didTapAction(for player: Player) {
        action(player)
    }
}
