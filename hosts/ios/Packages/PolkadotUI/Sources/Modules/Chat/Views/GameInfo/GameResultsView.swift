import SwiftUI
import DesignSystem

public struct GameResultsView: View, Hashable {
    @State private var avatars: [AvatarViewModel] = []

    private var viewModel: any GameResultsViewModelProtocol
    public init(viewModel: any GameResultsViewModelProtocol) {
        self.viewModel = viewModel
    }

    public static func == (lhs: GameResultsView, rhs: GameResultsView) -> Bool {
        AnyHashable(lhs.viewModel) == AnyHashable(rhs.viewModel)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(viewModel))
    }

    public var body: some View {
        VStack(spacing: 4) {
            cardView
            externalContentView(avatars)
        }
        .padding(.bottom, 24)
        .task(id: viewModel.shouldShowAction) {
            avatars = await viewModel.loadAvatars()
        }
    }

    private var cardView: some View {
        VStack(spacing: 8) {
            statusHeader
            Text(viewModel.formattedDateString())
                .font(.title24SemiBold())
                .foregroundStyle(Color(.textAndIconsPrimaryDark))
                .multilineTextAlignment(.center)
        }
        .padding(.all, 24)
        .frame(maxWidth: .infinity)
        .background(
            Color(.gameInfoCardBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusHeader: some View {
        if viewModel.status == .failed {
            Text(viewModel.statusMessage())
                .font(.title16SemiBold())
                .foregroundStyle(Color(.textAndIconsTertiaryDark))
        } else {
            HStack(spacing: 6) {
                Image(viewModel.status.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(viewModel.statusMessage())
                    .font(.title16SemiBold())
                    .foregroundStyle(viewModel.status.color)
            }
        }
    }
}

extension GameResultsView {
    @ViewBuilder
    private func externalContentView(_ avatars: [AvatarViewModel]) -> some View {
        VStack(spacing: 16) {
            if viewModel.shouldShowAction {
                chatWithPlayersButton(avatars)
            }

            if let additionalMessage = viewModel.additionalMessage() {
                Text(additionalMessage)
                    .font(.body14Regular())
                    .foregroundStyle(Color(.white69))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func chatWithPlayersButton(_ avatars: [AvatarViewModel]) -> some View {
        Button(action: viewModel.onAction) {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { index, avatar in
                        AvatarViewSUI(viewModel: avatar, size: 24)
                            .clipShape(Circle())
                            .background(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .zIndex(Double(avatars.count - index))
                    }
                }
                Text(.Game.resultActionChat)
                    .font(.title16SemiBold())
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Color(.prizesButtonDisabledBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .disabled(viewModel.isLoading)
    }
}

private extension GameResultStatus {
    var color: Color {
        switch self {
        case .pending:
            Color(.yellow)
        case .success:
            Color(.prizesStatusSuccess)
        case .failed:
            Color(.prizesStatusFailed)
        }
    }

    var icon: ImageResource {
        switch self {
        case .pending:
            .iconGameStatusPending
        case .success:
            .iconGameStatusSuccess
        case .failed:
            .iconGameStatusFail
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Success Cases") {
        ScrollView {
            VStack(spacing: 16) {
                // Success + Playing
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .success,
                    personhoodProgress: .playing(gamesLeft: 2, suspended: false),
                    shouldShowAction: true
                ))

                // Success + Playing + Was suspended
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .success,
                    personhoodProgress: .playing(gamesLeft: 2, suspended: true),
                    shouldShowAction: true
                ))

                // Success + Externally Recognized
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .success,
                    personhoodProgress: .externallyRecognized,
                    shouldShowAction: true
                ))

                // Success + Reached Personhood
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .success,
                    personhoodProgress: .reachedPersonhood,
                    shouldShowAction: true
                ))

                // Success + Unknown
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .success,
                    personhoodProgress: .unknown,
                    shouldShowAction: true
                ))
            }
        }
        .background(Color(.backgroundPrimary))
    }

    #Preview("Failed Cases") {
        ScrollView {
            VStack(spacing: 16) {
                // Failed + Playing
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .failed,
                    personhoodProgress: .playing(gamesLeft: 2, suspended: false),
                    shouldShowAction: true
                ))

                // Failed + Playing + Was suspended
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .failed,
                    personhoodProgress: .playing(gamesLeft: 2, suspended: true),
                    shouldShowAction: true
                ))

                // Failed + Externally Recognized
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .failed,
                    personhoodProgress: .externallyRecognized,
                    shouldShowAction: true
                ))

                // Failed + Unknown
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .failed,
                    personhoodProgress: .unknown,
                    shouldShowAction: true
                ))
            }
        }
        .background(Color(.backgroundPrimary))
    }

    #Preview("Pending") {
        ScrollView {
            VStack(spacing: 16) {
                // Failed + Playing + First time
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .pending,
                    personhoodProgress: .playing(gamesLeft: 2, suspended: false),
                    shouldShowAction: true
                ))
            }
        }
        .background(Color(.backgroundPrimary))
    }

    #Preview("Hidden Action") {
        ScrollView {
            VStack(spacing: 16) {
                GameResultsView(viewModel: GameResultsViewModel(
                    gameDate: Date.now,
                    status: .success,
                    personhoodProgress: .reachedPersonhood,
                    shouldShowAction: false
                ))
            }
        }
        .background(Color(.backgroundPrimary))
    }
#endif
