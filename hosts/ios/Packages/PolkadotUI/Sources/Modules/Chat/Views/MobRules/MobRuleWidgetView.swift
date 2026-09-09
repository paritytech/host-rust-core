import UIKit
import DesignSystem

final class MobRuleWidgetView: UIView, UIContentView {
    private let mainStack = UIStackView()
    private let headerContainerView = UIView()
    private let mobRuleContainerView = UIView()
    private let systemMessageContainerView = UIView()

    private weak var headerInfoView: (UIContentView & UIView)?
    private weak var mobRuleView: (UIContentView & UIView)?
    private weak var systemMessageLabel: MarkdownLabel?

    private var appliedConfiguration: MobRuleWidgetConfiguration

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set { apply(newValue) }
    }

    override var intrinsicContentSize: CGSize {
        UIView.layoutFittingCompressedSize
    }

    init(configuration: MobRuleWidgetConfiguration) {
        appliedConfiguration = configuration
        super.init(frame: .zero)
        setupViews()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.addArrangedSubview(headerContainerView)
        mainStack.addArrangedSubview(mobRuleContainerView)
        mainStack.addArrangedSubview(systemMessageContainerView)

        addSubview(mainStack)
        mainStack.snp.makeConstraints {
            $0.directionalHorizontalEdges.top.equalToSuperview()
            $0.bottom.equalToSuperview().inset(16)
        }
    }

    private func apply(_ any: UIContentConfiguration) {
        guard let configuration = any as? MobRuleWidgetConfiguration else { return }
        appliedConfiguration = configuration

        addHeaderIfNeeded()
        addMobRuleIfNeeded()
        addSystemMessageIfNeeded()
    }

    private func addHeaderIfNeeded() {
        guard let availableCasesCount = appliedConfiguration.availableCasesCount else {
            headerContainerView.setHidden(true)
            headerContainerView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        let configuration = ChatInfoMessageConfiguration.availableJudgeCasesMessages(
            count: availableCasesCount
        )

        if let headerInfoView {
            headerInfoView.configuration = configuration
        } else {
            let headerInfoView = configuration.makeContentView()
            self.headerInfoView = headerInfoView

            headerContainerView.addSubview(headerInfoView)
            headerInfoView.snp.makeConstraints {
                $0.directionalEdges.equalToSuperview()
            }
        }

        headerContainerView.setHidden(false)
    }

    private func addMobRuleIfNeeded() {
        guard let mobRuleModel = appliedConfiguration.activeCaseModel else {
            mobRuleContainerView.setHidden(true)
            mobRuleContainerView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        if let mobRuleView {
            mobRuleView.configuration = mobRuleModel
        } else {
            let mobRuleView = mobRuleModel.makeContentView()
            self.mobRuleView = mobRuleView

            mobRuleContainerView.addSubview(mobRuleView)
            mobRuleView.snp.makeConstraints {
                $0.directionalVerticalEdges.equalToSuperview()
                $0.leading.equalToSuperview().inset(16)
                $0.trailing.equalToSuperview()
            }
        }

        mobRuleContainerView.setHidden(false)
    }

    private func addSystemMessageIfNeeded() {
        guard let text = appliedConfiguration.systemMessage else {
            systemMessageContainerView.setHidden(true)
            systemMessageContainerView.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        if let systemMessageLabel {
            systemMessageLabel.text = text
        } else {
            let systemMessageLabel = MarkdownLabel()
            systemMessageLabel.typography = .bodyMedium
            systemMessageLabel.textColor = UIColor(resource: .textAndIconsSecondary)
            systemMessageLabel.numberOfLines = 0
            systemMessageLabel.text = text
            systemMessageLabel.textAlignment = .center

            self.systemMessageLabel = systemMessageLabel
            systemMessageContainerView.addSubview(systemMessageLabel)
            systemMessageLabel.snp.makeConstraints {
                $0.directionalEdges.equalToSuperview().inset(36)
            }
        }

        systemMessageContainerView.setHidden(false)
    }
}

#if DEBUG

    let text = """
    Thank you for contributing your judgments. You’ve completed all available cases. The app will notify you when new cases appear.
    """

    #Preview {
        MobRuleWidgetConfiguration(
            availableCasesCount: 5,
            activeCaseModel: MobRuleMessageConfiguration.collapsedVoting(),
            systemMessage: text
        ).makeContentView()
    }
#endif
