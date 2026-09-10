import Foundation
import UIKit_iOS
import UIKit
import DesignSystem

extension RoundedButton {
    func applyTipsStyle() {
        applyBaseFillStyle()
        roundedBackgroundView?.fillColor = .white12
        roundedBackgroundView?.highlightedFillColor = .white12
        roundedBackgroundView?.cornerRadius = 20
        contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 16)
        imageWithTitleView?.titleColor = .white100
        imageWithTitleView?.titleFont = UIFont.paragraphSmall
        imageWithTitleView?.spacingBetweenLabelAndIcon = 8

        changesContentOpacityWhenHighlighted = true
    }
}
