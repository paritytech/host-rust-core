import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class DiscardEvidenceViewLayout: BottomSheetBaseLayout {
    private let titleView: TopBottomLabelView = .create { view in
        view.topLabel.typography = .headlineSmall
        view.topLabel.textColor = .fgPrimary
        view.topLabel.numberOfLines = 0
        view.bottomLabel.typography = .paragraphLarge
        view.bottomLabel.textColor = .fgTertiary
        view.bottomLabel.numberOfLines = 0
        view.spacing = 8
    }

    private let actionView: GenericPairValueView<RoundedButton, RoundedButton> = .create { view in
        view.setHorizontalAndSpacing(8)
        view.fView.applyDestructiveStyle()
        view.sView.applyMainStyle()
        view.stackView.distribution = .fillEqually
    }

    private var titleLabel: UILabel {
        titleView.topLabel
    }

    private var descriptionLabel: UILabel {
        titleView.bottomLabel
    }

    var mainButton: RoundedButton {
        actionView.fView
    }

    var cancelButton: RoundedButton {
        actionView.sView
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupLayout() {
        super.setupLayout()
        contentView.addSubview(titleView)
        contentView.addSubview(actionView)

        titleView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }
        actionView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(titleView.snp.bottom).offset(16)
            make.height.equalTo(UIConstants.actionHeight)
        }
    }
}

extension DiscardEvidenceViewLayout {
    func bind(viewModel: DiscardEvidenceViewModel) {
        titleLabel.text = viewModel.title
        descriptionLabel.text = viewModel.description
        mainButton.imageWithTitleView?.title = viewModel.mainAction
        cancelButton.imageWithTitleView?.title = viewModel.cancelAction
    }
}
