import SwiftUI
import PolkadotUI
import DesignSystem

struct IdentityDetailsViewLayout: View {
    @State var viewModel: IdentityDetailsViewModelProtocol
    let isExpanded: Bool
    var onCardTapped: () -> Void = {}
    var onCollapse: (() -> Void)?

    init(
        viewModel: IdentityDetailsViewModelProtocol,
        isExpanded: Bool,
        onCardTapped: @escaping () -> Void = {},
        onCollapse: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.isExpanded = isExpanded
        self.onCardTapped = onCardTapped
        self.onCollapse = onCollapse
    }

    var body: some View {
        DSExpandableCardLayout(
            isExpanded: isExpanded,
            onCollapse: onCollapse,
            card: { card },
            details: { details }
        )
    }

    private var card: some View {
        IdentityDetailsCard(viewModel: viewModel, isExpanded: isExpanded)
            .onTapGesture { onCardTapped() }
    }

    private var details: some View {
        IdentityShareQrView(viewModel: viewModel)
            .clipShape(RoundedRectangle(cornerRadius: DSRadii.extraLarge))
            .containerShape(RoundedRectangle(cornerRadius: DSRadii.extraLarge))
            .padding(.bottom, DSSpacings.large)
    }
}
