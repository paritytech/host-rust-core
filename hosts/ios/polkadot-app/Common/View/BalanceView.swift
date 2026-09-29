import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class BalanceView: ControlView<
    UIView,
    GenericBorderedView<GenericPairValueView<Label, Label>>
> {
    var titleLabel: Label {
        controlContentView.contentView.sView
    }

    var amountLabel: Label {
        controlContentView.contentView.fView
    }

    var balanceBackgroundView: RoundedView {
        controlContentView.backgroundView
    }

    var balanceContentView: GenericPairValueView<Label, Label> {
        controlContentView.contentView
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configure()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight ?? 0)
    }

    private func configure() {
        changesContentOpacityWhenHighlighted = true
        preferredHeight = 28
        controlContentView.contentInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        balanceBackgroundView.applyBackgroundStyle(with: (preferredHeight ?? 0) / 2)

        balanceContentView.spacing = DSSpacings.extraSmall
        balanceContentView.makeHorizontal()

        titleLabel.typography = .bodyLarge
        titleLabel.textColor = .fgPrimaryInverted

        amountLabel.typography = .bodyLarge
        amountLabel.textColor = .fgPrimaryInverted
    }

    func apply(style: BalanceView.Style) {
        controlContentView.backgroundView.fillColor = style.background
        controlContentView.backgroundView.highlightedFillColor = style.background

        titleLabel.textColor = style.titleColor
        amountLabel.textColor = style.amountColor
    }

    func bind(amount: String) {
        amountLabel.text = amount

        setNeedsLayout()
    }
}

extension BalanceView {
    struct Style {
        let background: UIColor
        let titleColor: UIColor
        let amountColor: UIColor
    }
}

extension BalanceView.Style {
    static var normal: Self {
        .init(
            background: .clear,
            titleColor: .fgSecondary,
            amountColor: .fgPrimary
        )
    }

    static var error: Self {
        .init(
            background: .bgStatusError.withAlphaComponent(0.1),
            titleColor: .fgError,
            amountColor: .fgError
        )
    }
}
