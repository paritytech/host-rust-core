import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class DiscardDIMViewLayout: BottomSheetBaseLayout {
    private let titleView: TopBottomLabelView = .create { view in
        view.topLabel.typography = .headlineSmall
        view.topLabel.textColor = .fgPrimary
        view.topLabel.textAlignment = .center
        view.topLabel.numberOfLines = 0

        view.bottomLabel.typography = .paragraphLarge
        view.bottomLabel.textColor = .fgSecondary
        view.bottomLabel.textAlignment = .center
        view.bottomLabel.numberOfLines = 0

        view.spacing = 8
    }

    private let actionView: GenericPairValueView<
        RoundedButton,
        LoadableRoundedButton
    > = .create { view in
        let buttonTextColor = view.sView.contentView.imageWithTitleView?.titleColor
        view.sView.contentView.applyDestructiveStyle()
        view.sView.indicatorView.color = buttonTextColor ?? .textAndIconsPrimaryDark

        view.fView.applySecondaryStyle()

        view.setHorizontalAndSpacing(8)
        view.stackView.distribution = .fillEqually
    }

    private var titleLabel: UILabel {
        titleView.topLabel
    }

    private var descriptionLabel: UILabel {
        titleView.bottomLabel
    }

    var mainButton: RoundedButton {
        actionView.sView.contentView
    }

    var cancelButton: RoundedButton {
        actionView.fView
    }

    private(set) var activityInProgress: Bool = false

    override func setupLayout() {
        super.setupLayout()
        contentView.addSubview(titleView)
        contentView.addSubview(actionView)

        titleView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.trailing.equalToSuperview()
        }
        actionView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(titleView.snp.bottom).offset(40)
            make.height.equalTo(UIConstants.actionHeight)
        }
    }
}

extension DiscardDIMViewLayout {
    func bind(viewModel: DiscardDIMViewModel) {
        titleLabel.text = viewModel.title
        descriptionLabel.text = viewModel.description
        mainButton.imageWithTitleView?.title = viewModel.mainAction
        cancelButton.imageWithTitleView?.title = viewModel.cancelAction
    }

    func showActivity(active: Bool) {
        activityInProgress = active

        if active {
            mainButton.isEnabled = false
            cancelButton.isEnabled = false

            actionView.sView.startLoading()
        } else {
            actionView.sView.stopLoading()

            mainButton.isEnabled = true
            cancelButton.isEnabled = true
        }
    }
}
