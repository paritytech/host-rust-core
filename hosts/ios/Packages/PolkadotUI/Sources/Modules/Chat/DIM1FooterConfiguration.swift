import Foundation
import UIKit
internal import UIKit_iOS

public enum DIM1FooterConfiguration {
    @MainActor
    public static func footer(
        messages: [UIAction],
        action: UIAction?
    ) -> any HashableContentConfiguration {
        // TODO: temp solution, consider creating a separate content configuration
        let buttonConfig = UIViewContentConfiguration(
            id: "rounded-button",
            viewProvider: {
                guard let action else {
                    return UIView() // return empty view
                }
                let button = RoundedButton()
                button.snp.makeConstraints { make in
                    make.height.equalTo(52)
                }
                button.applyMainStyle()
                button.addAction(action, for: .touchUpInside)
                button.setTitle(action.title)

                let stack = UIStackView()
                stack.axis = .vertical
                stack.isLayoutMarginsRelativeArrangement = true
                stack.layoutMargins = .init(top: 0, left: 24, bottom: 0, right: 24)
                stack.addArrangedSubview(button)

                return stack
            }
        )

        let faqConfig = messages.isEmpty ? nil : FAQViewConfiguration(actions: messages)

        return GenericFooterConfiguration(
            faqConfiguration: faqConfig,
            contentConfiguration: buttonConfig
        )
    }

    public static func evidenceProvided() -> any HashableContentConfiguration {
        let viewModel = ChatSystemMessageTextView.ViewModel.text(
            String(localized: .dim1FooterEvidenceProvided)
        )

        let view = ChatSystemMessageTextView(viewModel: viewModel)
        return SwiftUIContentConfiguration(view: view)
    }

    public static func becomingPeer() -> any HashableContentConfiguration {
        let viewModel = ChatSystemMessageTextView.ViewModel.text(
            String(localized: .dim1FooterBecomingPeer)
        )

        let view = ChatSystemMessageTextView(viewModel: viewModel)
        return SwiftUIContentConfiguration(view: view)
    }

    public static func routeActions(actions: [ChatMessageActionView.ViewModel]) -> any HashableContentConfiguration {
        let view = ChatMessageActionList(actions: actions, padding: 16)
        return SwiftUIContentConfiguration(view: view)
    }

    public static func upgradeUsername(
        liteUsername: String,
        suggestedFullUsername: String,
        onUpgrade: @escaping () -> Void
    ) -> any HashableContentConfiguration {
        let viewModel = UpgradeUsernameViewModel(
            liteUsername: liteUsername,
            suggestedFullUsername: suggestedFullUsername,
            mode: .upgradeWidget(onUpgradeTap: onUpgrade)
        )

        let view = UpgradeUsernameView(viewModel: viewModel)
        return SwiftUIContentConfiguration(view: view)
    }

    public static func switchDIM(
        inProgress: Bool,
        handler: @escaping () -> Void
    ) -> any HashableContentConfiguration {
        let viewModel = SwitchDimFooterView.ViewModel(
            text: String(localized: .dim1FooterSwitchDim),
            inProgress: inProgress,
            action: handler
        )
        let view = SwitchDimFooterView(viewModel: viewModel)
        return SwiftUIContentConfiguration(view: view)
    }
}
