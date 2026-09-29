import SwiftUI
import DesignSystem

public struct MobRuleSuspendedFooterView: View, Hashable {
    let title: String
    let buttonTitle: String
    let onReclaim: () -> Void

    public init(
        title: String,
        buttonTitle: String,
        onReclaim: @escaping () -> Void
    ) {
        self.title = title
        self.buttonTitle = buttonTitle
        self.onReclaim = onReclaim
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .typography(.bodyMedium)
                .foregroundStyle(Color(.textAndIconsSecondary))
                .multilineTextAlignment(.center)

            Button(action: onReclaim) {
                Text(buttonTitle)
                    .typography(.titleSmall)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.mainDark)
        }
        .padding(24)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .inset(by: 0.5)
                .stroke(Color(.white12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    public static func == (lhs: MobRuleSuspendedFooterView, rhs: MobRuleSuspendedFooterView) -> Bool {
        lhs.title == rhs.title && lhs.buttonTitle == rhs.buttonTitle
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(buttonTitle)
    }
}

#if DEBUG
    #Preview {
        MobRuleSuspendedFooterView(
            title: "Your Peer Status Has Been Suspended. You cannot make judgements until you reclaim it.",
            buttonTitle: "Reclaim your Peer Status",
            onReclaim: {}
        )
        .background(Color(.black))
    }
#endif
