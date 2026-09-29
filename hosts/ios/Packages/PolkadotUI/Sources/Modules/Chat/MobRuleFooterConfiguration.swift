import SwiftUI

public enum MobRuleFooterConfiguration {
    public static func suspended(
        handler: @escaping () -> Void
    ) -> any HashableContentConfiguration {
        let view = MobRuleSuspendedFooterView(
            title: String(localized: .MobRule.suspendedMessage),
            buttonTitle: String(localized: .MobRule.suspendedAction),
            onReclaim: handler
        )
        return SwiftUIContentConfiguration(view: view)
    }
}
