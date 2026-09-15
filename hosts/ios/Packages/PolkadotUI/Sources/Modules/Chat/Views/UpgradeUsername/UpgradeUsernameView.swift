import SwiftUI
import DesignSystem

struct UpgradeUsernameView: View, Hashable {
    private let viewModel: UpgradeUsernameViewModel
    private let horizontalPaddingOverride: CGFloat?

    init(viewModel: UpgradeUsernameViewModel, horizontalPaddingOverride: CGFloat? = nil) {
        self.viewModel = viewModel
        self.horizontalPaddingOverride = horizontalPaddingOverride
    }

    var body: some View {
        VStack(spacing: 4) {
            cardView

            if case let .upgradeWidget(onUpgradeTap) = viewModel.mode {
                upgradeButton(onUpgradeTap: onUpgradeTap)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }
}

private extension UpgradeUsernameView {
    var horizontalPadding: CGFloat {
        if let horizontalPaddingOverride {
            return horizontalPaddingOverride
        }
        return switch viewModel.mode {
        case .upgradeWidget: 24
        case .upgradedMessage: 0
        }
    }

    var verticalPadding: CGFloat {
        switch viewModel.mode {
        case .upgradeWidget: 12
        case .upgradedMessage: 0
        }
    }

    var cardDescription: LocalizedStringResource {
        if case .upgradedMessage = viewModel.mode {
            .usernameUpgraded
        } else {
            .usernameUpgradeDescription
        }
    }

    var cardHeaderTitle: LocalizedStringResource {
        if case .upgradedMessage = viewModel.mode {
            .usernameUpgradedTitle
        } else {
            .usernameUpgradeTitle
        }
    }

    var cardHeaderSubtitle: LocalizedStringResource {
        if case .upgradedMessage = viewModel.mode {
            .usernameUpgradedSubtitle
        } else {
            .usernameUpgradeSubtitle
        }
    }

    @ViewBuilder
    var cardView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(cardHeaderTitle)
                    .typography(.titleMedium)
                    .foregroundColor(Color(.textAndIconsTertiaryDark))

                Text(viewModel.suggestedFullUsername)
                    .typography(.headlineLarge)
                    .foregroundColor(Color(.textAndIconsPrimaryDark))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color(.systemSuccess).opacity(0.12))
                            .stroke(Color(.systemSuccess), lineWidth: 2)
                    )

                Text(cardHeaderSubtitle)
                    .typography(.paragraphLarge)
                    .foregroundColor(Color(.textAndIconsTertiaryDark))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 16)
            .background(
                Color(.bgChatSurfaceContainer)
            )

            Text(cardDescription)
                .typography(.paragraphLarge)
                .foregroundColor(Color(.textAndIconsPrimaryDark))
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
        }
        .background(Color(.bgChatSurfaceMain))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.white12), lineWidth: 1)
        }
    }

    @ViewBuilder
    func upgradeButton(onUpgradeTap: @escaping () -> Void) -> some View {
        Button {
            onUpgradeTap()
        } label: {
            ZStack {
                Text(.usernameStartUpgrading)
                    .typography(.titleMedium)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.mainWhite)
    }
}

#Preview {
    UpgradeUsernameView(viewModel: .init(
        liteUsername: "username",
        suggestedFullUsername: "long.long.logn.username",
        mode: .upgradeWidget(onUpgradeTap: {})
    ))
}
