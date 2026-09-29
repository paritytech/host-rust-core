import SwiftUI
import UIKit
import DesignSystem

// MARK: - Views

public struct ChatWithPlayersView: View {
    public typealias ViewModel = ChatWithPlayersViewModelProtocol
    @State public var viewModel: ViewModel = ChatWithPlayersViewModel()

    public init() {}

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 1)
    ]

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.players) { player in
                    PlayerCell(player: player) {
                        viewModel.didTapAction(for: player)
                    }
                    .padding(12)
                }
            }
            .padding(16)
        }
        .background(Color(.backgroundPrimary))
    }
}

struct PlayerCell: View {
    let player: Player
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            AvatarViewSUI(viewModel: avatarViewModel, size: 81)

            LoadableButton(
                isLoading: player.isLoading,
                action: action
            ) {
                Text(buttonTitle)
                    .typography(.titleSmall)
                    .frame(maxWidth: .infinity)
            }
            .tint(Color(.textAndIconsPrimaryDark))
            .buttonStyle(buttonStyle)
            .frame(maxWidth: 88)
        }
    }

    private var avatarViewModel: AvatarViewModel {
        if let image = player.image {
            .image(image)
        } else {
            .colored(
                text: String(player.username.prefix(1)),
                colorSeed: player.id
            )
        }
    }

    private var buttonStyle: MainButtonStyle {
        if player.isContact {
            MainButtonStyle(
                backgroundColor: Color(.textAndIconsPrimaryDark),
                foregroundColor: Color(.textAndIconsPrimaryLight),
                height: 36
            )
        } else {
            MainButtonStyle(
                backgroundColor: Color(.fill12),
                foregroundColor: Color(.textAndIconsPrimaryDark),
                height: 36
            )
        }
    }

    private var buttonTitle: LocalizedStringResource {
        player.isContact ? .Game.playerActionMessage : .Game.playerActionAdd
    }
}

#Preview {
    ChatWithPlayersView()
}
