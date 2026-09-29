import UIKit
import PolkadotUI
import DesignSystem

final class EvidenceTipsViewLayout: PageSheetBaseLayout {
    private let mainIcon: RowView<UIImageView> = .create { view in
        view.rowContentView.contentMode = .center
    }

    private let titleContainer: RowView<Label> = .create { view in
        view.rowContentView.numberOfLines = 0
        view.rowContentView.textAlignment = .left
        view.rowContentView.typography = .headlineSmall
        view.rowContentView.textColor = .fgPrimary
    }

    private let stepsTableView: StackTableView = .init(frame: .zero, style: .clearStyle)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStyle()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupStyle() {
        contentView.layoutInsets = UIEdgeInsets(
            top: UIConstants.verticalInsetMedium,
            left: 0,
            bottom: 0,
            right: 0
        )
        stepsTableView.hasSeparators = true
        stepsTableView.stackView.spacing = UIConstants.verticalInsetMedium
        stepsTableView.contentInsets = .zero
    }

    override func setupLayout() {
        super.setupLayout()
        contentView.addArrangedSubview(mainIcon, spacingAfter: 32)
        contentView.addArrangedSubview(titleContainer, spacingAfter: 32)
        contentView.addArrangedSubview(stepsTableView)
    }
}

extension EvidenceTipsViewLayout {
    func bind(viewModel: EvidenceTipsViewModel) {
        stepsTableView.stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        mainIcon.rowContentView.image = viewModel.icon

        titleContainer.rowContentView.text = viewModel.title
        viewModel.steps.forEach { stepViewModel in
            let stepView = EvidenceTipsStepView()
            stepView.bind(viewModel: stepViewModel)
            stepsTableView.addArrangedSubview(stepView)
        }
    }
}
