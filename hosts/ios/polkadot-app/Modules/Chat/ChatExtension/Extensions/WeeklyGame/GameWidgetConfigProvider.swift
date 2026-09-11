import SwiftUI
import PolkadotUI

struct GameWidgetConfigProvider {
    enum Action {
        case register
        case upgradeUsername
    }

    // MARK: - Game State Data

    let model: Model
    let onAction: (Action, AnyHashable) -> Void

    // MARK: - Nested Types

    struct Model: Hashable {
        let gameState: GameState?
        let isLoading: Bool
        let isRegisterEnabled: Bool
        let actionViewModels: [ChatMessageActionView.ViewModel]
        let upgradeUsername: UpgradeUsernameData?
        let onActionContext: AnyHashable
    }

    enum GameState: Hashable {
        case register(gameDate: Date)
        case registered(gameDate: Date)
        case starting(gameDate: Date)
    }

    struct UpgradeUsernameData: Hashable {
        let liteUsername: String
        let suggestedFullUsername: String
    }

    // MARK: - View Model Creation

    @MainActor
    private func makeViewModel() -> GameWidgetViewModel? {
        let stateViewModel = makeStateViewModel()
        let upgradeUsernameViewModel = makeUpgradeUsernameViewModel()
        if model.actionViewModels.isEmpty,
           stateViewModel == nil,
           upgradeUsernameViewModel == nil {
            return nil
        }
        return GameWidgetViewModel(
            actionViewModels: model.actionViewModels,
            stateViewModel: stateViewModel,
            upgradeUsernameViewModel: upgradeUsernameViewModel
        )
    }

    @MainActor
    private func makeStateViewModel() -> GameStateViewModel? {
        guard let gameState = model.gameState else { return nil }

        let state: GameStateViewModel.State =
            switch gameState {
            case let .register(gameDate):
                .register(gameDate: gameDate)
            case let .registered(gameDate):
                .registered(gameDate: gameDate)
            case let .starting(gameDate):
                .starting(gameDate: gameDate)
            }

        let viewModel = GameStateViewModel(
            state: state,
            isLoading: model.isLoading,
            isRegisterEnabled: model.isRegisterEnabled,
            countdownFormatter: CountdownDateFormatter()
        )

        viewModel.onRegister = { [onAction, model] in onAction(.register, model.onActionContext) }

        return viewModel
    }

    @MainActor
    private func makeUpgradeUsernameViewModel() -> UpgradeUsernameViewModel? {
        guard let upgradeUsername = model.upgradeUsername else { return nil }

        return UpgradeUsernameViewModel(
            liteUsername: upgradeUsername.liteUsername,
            suggestedFullUsername: upgradeUsername.suggestedFullUsername,
            mode: .upgradeWidget(
                onUpgradeTap: { [onAction, model] in onAction(.upgradeUsername, model.onActionContext) }
            )
        )
    }
}

extension GameWidgetConfigProvider {
    @MainActor
    func configuration() -> (any HashableContentConfiguration)? {
        guard let viewModel = makeViewModel() else {
            return nil
        }
        let widget = GameWidget(viewModel: viewModel)
        return SwiftUIContentConfiguration(view: widget, id: model)
    }
}

// MARK: - Equatable & Hashable (ignoring closure)

extension GameWidgetConfigProvider: Equatable {
    static func == (lhs: GameWidgetConfigProvider, rhs: GameWidgetConfigProvider) -> Bool {
        lhs.model == rhs.model
    }
}

extension GameWidgetConfigProvider: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(model)
    }
}
