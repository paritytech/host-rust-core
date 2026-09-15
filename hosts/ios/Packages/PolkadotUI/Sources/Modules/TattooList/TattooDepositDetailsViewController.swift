import SwiftUI
import DesignSystem

public final class TattooDepositDetailsViewController: UIHostingController<TattooDepositDetailsView> {
    private var viewModel: ViewModel

    public init(requiredAmount: String) {
        let viewModel = ViewModel(
            requiredAmount: requiredAmount,
            inProgress: false,
            actionHandler: {}
        )
        let view = TattooDepositDetailsView(
            requiredAmount: viewModel.requiredAmount,
            inProgress: viewModel.inProgress,
            onDepositTapped: viewModel.actionHandler
        )
        self.viewModel = viewModel
        super.init(rootView: view)
    }

    @available(*, unavailable)
    @MainActor @preconcurrency dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

public extension TattooDepositDetailsViewController {
    struct ViewModel {
        let requiredAmount: String
        let inProgress: Bool
        let actionHandler: () -> Void

        public init(
            requiredAmount: String,
            inProgress: Bool,
            actionHandler: @escaping () -> Void
        ) {
            self.requiredAmount = requiredAmount
            self.inProgress = inProgress
            self.actionHandler = actionHandler
        }
    }

    func bind(viewModel: ViewModel) {
        self.viewModel = viewModel
        rootView.requiredAmount = viewModel.requiredAmount
        rootView.onDepositTapped = viewModel.actionHandler
        rootView.inProgress = viewModel.inProgress
    }
}

public struct TattooDepositDetailsView: View {
    var requiredAmount: String
    var inProgress: Bool
    var onDepositTapped: () -> Void = {}

    public var body: some View {
        BottomSheetBaseView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(.Game.depositRequiredLabel)
                        .typography(.titleMedium)
                        .textCase(.uppercase)
                        .foregroundColor(Color(.textAndIconsSecondary))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(.depositRequiredTitle(requiredAmount))
                        .typography(.headlineSmall)
                        .foregroundColor(Color(.textAndIconsPrimaryDark))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(.depositRequiredDescription)
                        .typography(.paragraphLarge)
                        .foregroundColor(Color(.textAndIconsSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(8)

                LoadableButton(
                    isLoading: inProgress,
                    action: onDepositTapped
                ) {
                    Text(.Game.depositRequiredButton(requiredAmount))
                        .typography(.titleMedium)
                        .frame(maxWidth: .infinity)
                }
                .tint(Color(.textAndIconsPrimaryLight))
                .buttonStyle(.mainWhite)
            }
        }
    }
}

#Preview {
    TattooDepositDetailsViewController(requiredAmount: "10")
}
