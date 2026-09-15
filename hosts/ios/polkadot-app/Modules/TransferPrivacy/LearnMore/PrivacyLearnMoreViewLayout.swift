import SwiftUI
import PolkadotUI
import DesignSystem

struct PrivacyLearnMoreView: View {
    let models: [PrivacyLearnMoreModel]
    var onBack: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            backButton
            VStack(alignment: .leading, spacing: 16) {
                ForEach(models, id: \.title) { model in
                    section(model: model)
                }
            }
        }
        .padding([.horizontal, .top], DSSpacings.large)
        .padding(.bottom, 32)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(.iconArrowBack)
                .renderingMode(.template)
                .foregroundStyle(.fgPrimary)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    private func section(model: PrivacyLearnMoreModel) -> some View {
        VStack(alignment: .leading, spacing: DSSpacings.mediumIncreased) {
            Text(model.title)
                .typography(.headlineSmall)
                .foregroundStyle(.fgPrimary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.details, id: \.self) { paragraph in
                    Text(paragraph)
                        .typography(.bodyMedium)
                        .foregroundStyle(.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
