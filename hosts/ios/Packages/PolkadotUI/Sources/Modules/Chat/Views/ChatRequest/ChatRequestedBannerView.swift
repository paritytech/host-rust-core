import DesignSystem
import SwiftUI
import FoundationExt

public struct ChatRequestedBannerView: View {
    @State var viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Text(
            getMessage(for: viewModel.username)
        )
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 24)
    }
}

public extension ChatRequestedBannerView {
    struct ViewModel {
        let username: String
        let isFromGame: Bool

        public init(
            username: String,
            isFromGame: Bool
        ) {
            self.username = username
            self.isFromGame = isFromGame
        }
    }
}

private extension ChatRequestedBannerView {
    func getMessage(for username: String) -> AttributedString {
        let defaultAttributes = LabelStyle.body14Regular().attributes(
            for: .center,
            textColor: UIColor.fgTertiary
        )

        guard !viewModel.isFromGame else {
            return NSAttributedString(
                string: String(localized: .chatRequestedBannerGameMessage),
                attributes: defaultAttributes
            )
            .toAttributedStringOrEmpty()
        }

        let highlightingAttributes = LabelStyle.body14SemiBold().attributes(
            for: .center,
            textColor: UIColor.fgTertiary
        )

        return NSAttributedString.highlightedItems(
            [username],
            formattingClosure: { items in
                String(localized: .chatRequestedBannerMessage(username: items[0]))
            },
            highlightingAttributes: highlightingAttributes,
            defaultAttributes: defaultAttributes
        )
        .toAttributedStringOrEmpty()
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    UIHostingConfiguration {
        ChatRequestedBannerView(
            viewModel: .init(username: "Maxwell.42", isFromGame: false)
        )
        .background(Color.bgSurfaceContainer)
    }
    .makeContentView()
}
