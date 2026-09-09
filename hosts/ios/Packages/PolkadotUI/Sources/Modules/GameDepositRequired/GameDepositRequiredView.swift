import SwiftUI
import DesignSystem

public struct GameDepositRequiredView: View {
    public var requiredAmount: String
    public var onDepositTapped: () -> Void = {}

    public init(
        requiredAmount: String,
        onDepositTapped: @escaping () -> Void = {}
    ) {
        self.requiredAmount = requiredAmount
        self.onDepositTapped = onDepositTapped
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            BottomSheetBaseView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(.Game.depositRequiredLabel)
                        .typography(.titleMedium)
                        .textCase(.uppercase)
                        .foregroundColor(Color(.textAndIconsSecondary))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(.Game.depositRequiredTitle(requiredAmount))
                        .typography(.headlineSmall)
                        .foregroundColor(Color(.textAndIconsPrimaryDark))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    Text(.Game.depositRequiredDescription)
                        .typography(.paragraphLarge)
                        .foregroundColor(Color(.textAndIconsSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    Button(action: onDepositTapped) {
                        Text(.Game.depositRequiredButton(requiredAmount))
                            .typography(.titleMedium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.mainWhite)
                    .padding(.top, 24)
                }
            }
        }
    }
}

#Preview {
    GameDepositRequiredView(requiredAmount: "$50")
}
