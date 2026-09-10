import Foundation
import UIKit.UIColor
import SwiftUI

public extension ChatSystemMessageConfiguration {
    // TODO: Discuss why do we need to use ChatSystemMessage insted of any Content provider
    static func anyView(_ view: some View & Hashable) -> Self {
        ChatSystemMessageConfiguration(
            contentProvider: SwiftUIContentConfiguration(view: view)
        )
    }

    static func gameResults(
        gameDate: Date,
        state: GameResultStatus,
        personhoodProgress: GamePersonhoodProgress,
        showChat: Bool,
        avatarProvider: (() async -> [AvatarViewModel])?,
        action: @escaping () -> Void
    ) -> Self {
        let viewModel = GameResultsViewModel(
            gameDate: gameDate,
            status: state,
            personhoodProgress: personhoodProgress,
            isLoading: false,
            shouldShowAction: showChat,
            avatarProvider: avatarProvider
        )

        viewModel.onAction = action

        let view = GameResultsView(viewModel: viewModel)
        let configuration = SwiftUIContentConfiguration(view: view)

        let bgConfig = ChatSystemMessageConfiguration.BackgroundConfiguration(
            color: .clear,
            cornerRadius: 0,
            insets: .all(insets: 0)
        )

        return ChatSystemMessageConfiguration(
            contentProvider: configuration,
            textBackgroundConfiguration: bgConfig,
            contentInsets: .zero
        )
    }

    static func deposit(
        amount: String
    ) -> Self {
        let text = String(localized: .chatDepositAdded(amount: amount))
        return ChatSystemMessageConfiguration.text(.text(text))
    }

    static func text(_ viewModel: ChatSystemMessageTextView.ViewModel) -> Self {
        let view = ChatSystemMessageTextView(viewModel: viewModel)
        let configuration = SwiftUIContentConfiguration(view: view)

        let bgConfig = ChatSystemMessageConfiguration.BackgroundConfiguration(
            color: .clear,
            cornerRadius: 0,
            insets: .all(insets: 0)
        )

        return ChatSystemMessageConfiguration(
            contentProvider: configuration,
            textBackgroundConfiguration: bgConfig,
            contentInsets: .init(horizontal: 0, vertical: 12)
        )
    }

    static func fullUsernameClaimed(
        liteUsername: String,
        fullUsername: String
    ) -> Self {
        let viewModel = UpgradeUsernameViewModel(
            liteUsername: liteUsername,
            suggestedFullUsername: fullUsername,
            mode: .upgradedMessage
        )
        let view = UpgradeUsernameView(viewModel: viewModel)
        let configuration = SwiftUIContentConfiguration(view: view)

        let bgConfig = ChatSystemMessageConfiguration.BackgroundConfiguration(
            color: .clear,
            cornerRadius: 0,
            insets: .init(horizontal: 0, vertical: 16)
        )

        return ChatSystemMessageConfiguration(
            contentProvider: configuration,
            textBackgroundConfiguration: bgConfig,
            contentInsets: .zero
        )
    }

    static func personhoodRegistered() -> Self {
        ChatSystemMessageConfiguration.text(.parts([
            .bold(.init(localized: .chatPersonhoodRegisteredPrefix)),
            .plain(.init(localized: .chatPersonhoodRegisteredMessage))
        ]))
    }
}
