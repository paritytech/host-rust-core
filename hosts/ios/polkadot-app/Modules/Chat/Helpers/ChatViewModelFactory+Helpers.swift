import Foundation
import PolkadotUI
import UIKit.UIImage

extension ChatMetadata {
    var chatContactInfo: ChatHeaderConfiguration {
        let avatarViewModel: AvatarViewModel = {
            if let image = peerMetadata.icon.image {
                return .image(image)
            }

            let prefix = String(peerMetadata.name.prefix(1))
            return .colored(text: prefix, colorSeed: chatId.colorSeed)
        }()

        let info: String? =
            switch peerMetadata.contactSource {
            case .chat:
                nil
            case .game(_, nil):
                String(localized: .contactSourceDescriptionGameGeneric)
            case let .game(_, date):
                date?.formatted(.gameConnectionInfo)
            }

        return ChatHeaderConfiguration(
            avatarViewModel: avatarViewModel,
            username: peerMetadata.name,
            additionalInfo: info
        )
    }
}

extension Chat.LocalMessage.Content.Transfer.Status {
    var viewStatus: ChatTransferMessageConfiguration.State {
        switch self {
        case .processing:
            .processing
        case .sent:
            .sent
        case .claiming:
            .claiming
        case .partiallyClaimed:
            .partiallyClaimed
        case .finished:
            .finished
        case .error:
            .error
        }
    }
}

extension UIAction {
    static func chatReply(_ action: @escaping () -> Void) -> UIAction {
        UIAction(
            title: String(localized: .chatReply),
            image: UIImage(resource: .reply).withTintColor(.fgPrimary, renderingMode: .alwaysOriginal)
        ) { _ in
            action()
        }
    }

    static func chatEdit(_ action: @escaping () -> Void) -> UIAction {
        UIAction(
            title: String(localized: .chatEdit),
            image: UIImage(resource: .edit).withTintColor(.fgPrimary, renderingMode: .alwaysOriginal)
        ) { _ in
            action()
        }
    }

    static func chatCopy(_ action: @escaping () -> Void) -> UIAction {
        UIAction(
            title: String(localized: .chatCopy),
            image: UIImage(resource: .copy).withTintColor(.fgPrimary, renderingMode: .alwaysOriginal)
        ) { _ in
            action()
        }
    }

    static func chatEditHistory(_ action: @escaping () -> Void) -> UIAction {
        UIAction(
            title: String(localized: .chatEditHistory),
            image: UIImage(resource: .history).withTintColor(.fgPrimary, renderingMode: .alwaysOriginal)
        ) { _ in
            action()
        }
    }
}
