import SwiftUI
import DesignSystem

public struct SwitchDimFooterView: View, Hashable {
    let viewModel: ViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack {
            Text(viewModel.text)
                .typography(.bodyMedium)
                .foregroundStyle(Color.fgSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            LoadableButton(isLoading: viewModel.inProgress) {
                viewModel.action()
            } label: {
                Text(String(localized: .dimFooterSwitchActionTitle))
                    .typography(.bodyMedium)
                    .foregroundStyle(Color.fgPrimary)
                    .padding(.horizontal, 32)
            }
            .tint(Color.fgPrimary)
            .buttonStyle(.mainDark44)
        }
    }
}

public extension SwitchDimFooterView {
    struct ViewModel: Hashable {
        let text: String
        let inProgress: Bool
        let action: () -> Void

        public init(text: String, inProgress: Bool, action: @escaping () -> Void) {
            self.text = text
            self.inProgress = inProgress
            self.action = action
        }

        public static func == (lhs: SwitchDimFooterView.ViewModel, rhs: SwitchDimFooterView.ViewModel) -> Bool {
            lhs.text == rhs.text &&
                lhs.inProgress == rhs.inProgress
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(text)
            hasher.combine(inProgress)
        }
    }
}

#Preview {
    SwitchDimFooterView(
        viewModel: .init(
            text: String(localized: .dim1FooterSwitchDim),
            inProgress: true,
            action: {}
        )
    )
}
