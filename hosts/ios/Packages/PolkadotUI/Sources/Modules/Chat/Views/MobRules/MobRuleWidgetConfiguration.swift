import UIKit

public struct MobRuleWidgetConfiguration: HashableContentConfiguration {
    let availableCasesCount: Int?

    let activeCaseModel: MobRuleMessageConfiguration?

    let systemMessage: String?

    public init(
        availableCasesCount: Int?,
        activeCaseModel: MobRuleMessageConfiguration?,
        systemMessage: String?
    ) {
        self.availableCasesCount = availableCasesCount
        self.activeCaseModel = activeCaseModel
        self.systemMessage = systemMessage
    }

    public func makeContentView() -> any UIView & UIContentView {
        MobRuleWidgetView(configuration: self)
    }
}
