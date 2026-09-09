import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class EvidenceTipsStepView: RowView<TitleValueHorizontalView<
    GenericBackgroundView<Label>,
    TopBottomLabelView
>> {
    var stepLabel: Label { rowContentView.titleView.wrappedView }
    var titleLabel: Label { rowContentView.valueView.topLabel }
    var descriptionLabel: Label { rowContentView.valueView.bottomLabel }

    convenience init() {
        self.init(style: RowViewStyle.defaultStyle)

        setupStyle()
    }

    private func setupStyle() {
        titleLabel.typography = .titleLarge
        titleLabel.textColor = .fgPrimary
        descriptionLabel.typography = .paragraphLarge
        descriptionLabel.textColor = .fgSecondary
        stepLabel.typography = .titleSmall
        stepLabel.textColor = .fgPrimary
        rowContentView.stackView.alignment = .top
        rowContentView.titleView.mode = .centered
        rowContentView.titleView.style = .roundedTertiary6
        rowContentView.spacing = 16
        rowContentView.valueView.spacing = 8
        rowContentView.titleView.snp.makeConstraints { make in
            make.height.equalTo(24)
            make.width.equalTo(rowContentView.titleView.snp.height)
        }
        titleLabel.numberOfLines = 0
        descriptionLabel.numberOfLines = 0
        rowContentView.stackView.isLayoutMarginsRelativeArrangement = true
        rowContentView.stackView.layoutMargins = .init(
            top: 0,
            left: 0,
            bottom: UIConstants.verticalInsetMedium,
            right: 0
        )
    }

    func bind(viewModel: EvidenceTipsViewModel.Step) {
        stepLabel.text = viewModel.step
        titleLabel.text = viewModel.title
        descriptionLabel.text = viewModel.description
    }
}
