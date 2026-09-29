import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class TattooConfirmViewLayout: BottomSheetBaseLayout {
    // overrides top inset to saticfy desing (BottomSheetBaseLayout insets discussion needed)
    override var contentInsets: UIEdgeInsets {
        var insets = super.contentInsets
        insets.top = 24
        return insets
    }

    let titleView: TopBottomLabelView = .create { view in
        view.topLabel.typography = .headlineLarge
        view.topLabel.textColor = .textAndIconsPrimaryDark
        view.topLabel.numberOfLines = 0
        view.bottomLabel.typography = .paragraphLarge
        view.bottomLabel.textColor = .textAndIconsTertiaryDark
        view.bottomLabel.numberOfLines = 0
        view.spacing = 8
    }

    var titleLabel: UILabel {
        titleView.topLabel
    }

    var subtitleLabel: UILabel {
        titleView.bottomLabel
    }

    let actionView: GenericPairValueView<RoundedButton, RoundedButton> = .create { view in
        view.setHorizontalAndSpacing(8)
        view.fView.applySecondaryStyle()
        view.sView.applyMainStyle()
        view.stackView.distribution = .fillEqually
    }

    var cancelButton: RoundedButton {
        actionView.fView
    }

    var confirmButton: RoundedButton {
        actionView.sView
    }

    override func setupLayout() {
        super.setupLayout()

        contentView.addSubview(titleView)
        titleView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }

        contentView.addSubview(actionView)
        actionView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(UIConstants.actionHeight)
            make.top.equalTo(titleView.snp.bottom).offset(24)
        }
    }
}
