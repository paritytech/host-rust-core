import SwiftUI

public struct GameWidget: View, Hashable {
    public var viewModel: any GameWidgetViewModelProtocol

    public init(viewModel: any GameWidgetViewModelProtocol) {
        self.viewModel = viewModel
    }

    public static func == (lhs: GameWidget, rhs: GameWidget) -> Bool {
        AnyHashable(lhs.viewModel) == AnyHashable(rhs.viewModel)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(viewModel))
    }

    public var body: some View {
        VStack(spacing: 8) {
            if !viewModel.actionViewModels.isEmpty {
                ChatMessageActionList(actions: viewModel.actionViewModels)
                    .padding(.horizontal, 16)
            }
            if let upgradeVM = viewModel.upgradeUsernameViewModel {
                UpgradeUsernameView(viewModel: upgradeVM, horizontalPaddingOverride: 16)
            }
            if let stateVM = viewModel.stateViewModel {
                GameStateView(viewModel: stateVM)
            }
        }
    }
}
