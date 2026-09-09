import UIKit
import DesignSystem
import PolkadotUI

extension UIContentUnavailableConfiguration {
    static func titleSubtitle(
        with title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> UIContentUnavailableConfiguration {
        var configuration = titleSubtitle(with: title, subtitle: subtitle)

        var titleAttributes = AttributeContainer()
        titleAttributes.font = UIFont.app(.titleMedium.emphasized)

        var button = UIButton.Configuration.borderedProminent()
        button.attributedTitle = AttributedString(actionTitle, attributes: titleAttributes)
        button.baseBackgroundColor = .bgActionPrimary
        button.baseForegroundColor = .fgPrimaryInverted

        configuration.button = button
        configuration.buttonProperties.primaryAction = UIAction { _ in action() }

        return configuration
    }

    static func titleSubtitle(with title: String, subtitle: String) -> UIContentUnavailableConfiguration {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = nil

        configuration.textProperties.font = UIFont.titleMedium
        configuration.textProperties.color = .fgPrimary
        configuration.text = title

        configuration.secondaryTextProperties.font = UIFont.bodyMedium
        configuration.secondaryTextProperties.color = .fgTertiary
        configuration.secondaryTextProperties.numberOfLines = 0
        configuration.secondaryText = subtitle

        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24)

        configuration.textToSecondaryTextPadding = 12

        return configuration
    }
}
