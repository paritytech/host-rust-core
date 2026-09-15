import UIKit
import DesignSystem
import ExternalAccessibility
internal import SnapKit

public struct ChatTransferMessageConfiguration: HashableContentConfiguration {
    let title: String
    let amountText: String
    let tokenSymbol: String
    let originalAmountText: String?
    let state: ChatTransferMessageConfiguration.DirectionalState
    let statusConfiguration: ChatMessageStatusViewConfiguration
    let backgroundColor: UIColor
    let titleColor: UIColor
    let amountBackgroundColor: UIColor
    let amountTextColor: UIColor
    let originalAmountTextColor: UIColor
    let side: ChatBubbleTailSide

    public func makeContentView() -> any UIView & UIContentView {
        ChatTransferMessageView(configuration: self)
    }

    public func updated(for _: UIConfigurationState) -> Self { self }
}

public extension ChatTransferMessageConfiguration {
    enum DirectionalState: Hashable {
        case incoming(State)
        case outgoing(State)
    }

    enum State: Hashable {
        case processing
        case sent
        case claiming
        /// Some coins received, the rest still being claimed (a retry is in flight).
        case partiallyClaimed
        case finished
        case error
    }
}

final class ChatTransferMessageView: UIView, UIContentView, ReactableContentView {
    private let bubbleView = ChatBubbleView()

    private let titleLabel: Label = create {
        $0.lineBreakMode = .byTruncatingMiddle
        $0.typography = .paragraphLarge
        $0.numberOfLines = 1
        $0.textAlignment = .left
    }

    private let amountContainerView: GenericBackgroundView<GenericPairValueView<TopBottomLabelView, Label>> =
        create { container in
            container.insets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

            let pair = container.wrappedView
            pair.setVerticalAndSpacing(0)
            pair.stackView.alignment = .center

            let amounts = pair.fView
            amounts.stackView.spacing = 0

            amounts.topLabel.typography = .bodyMedium
            amounts.topLabel.numberOfLines = 1
            amounts.topLabel.textAlignment = .center
            amounts.topLabel.isHidden = true

            amounts.bottomLabel.typography = .headlineLarge
            amounts.bottomLabel.numberOfLines = 1
            amounts.bottomLabel.textAlignment = .center

            let symbol = pair.sView
            symbol.typography = .bodyMedium
            symbol.textColor = .fgSecondary
            symbol.numberOfLines = 1
            symbol.textAlignment = .center
        }

    private var receivedAmountLabel: Label {
        amountContainerView.wrappedView.fView.bottomLabel
    }

    private var originalAmountLabel: Label {
        amountContainerView.wrappedView.fView.topLabel
    }

    private var tokenSymbolLabel: Label {
        amountContainerView.wrappedView.sView
    }

    private let subtitleIconView: UIImageView = create {
        $0.contentMode = .scaleAspectFit
    }

    private let subtitleLabel: Label = create {
        $0.typography = .bodySmallEmphasized
        $0.numberOfLines = 2
        $0.textAlignment = .left
        $0.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
    }

    private let subtitleStackView: UIStackView = create {
        $0.axis = .horizontal
        $0.alignment = .center
        $0.spacing = 4
    }

    private lazy var statusView = appliedConfiguration.statusConfiguration.makeContentView()

    private var bubbleLeadingConstraint: Constraint?
    private var bubbleTrailingConstraint: Constraint?

    private var appliedConfiguration: ChatTransferMessageConfiguration

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set { apply(newValue) }
    }

    var leadingReactionsAlignmentView: UIView {
        titleLabel
    }

    init(configuration: ChatTransferMessageConfiguration) {
        appliedConfiguration = configuration
        super.init(frame: .zero)
        setupViews()
        apply(configuration)
        applyAccessibilityBindings()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        addSubview(bubbleView)
        subtitleStackView.addArrangedSubview(subtitleIconView)
        subtitleStackView.addArrangedSubview(subtitleLabel)

        bubbleView.addSubview(titleLabel)
        bubbleView.addSubview(amountContainerView)
        bubbleView.addSubview(subtitleStackView)
        bubbleView.addSubview(statusView)

        bubbleView.snp.makeConstraints {
            $0.width.lessThanOrEqualToSuperview().multipliedBy(0.85)
            $0.top.equalToSuperview()
            bubbleLeadingConstraint = $0.leading.equalToSuperview().constraint
            bubbleTrailingConstraint = $0.trailing.equalToSuperview().constraint
            $0.bottom.equalToSuperview().priority(.medium)
        }

        titleLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(14)
            $0.trailing.lessThanOrEqualToSuperview().inset(14)
            $0.top.equalToSuperview().offset(12)
        }

        amountContainerView.snp.makeConstraints {
            $0.width.greaterThanOrEqualTo(150).priority(.medium)
            $0.leading.equalToSuperview().offset(14)
            $0.trailing.equalToSuperview().inset(14)
            $0.top.equalTo(titleLabel.snp.bottom).offset(8)
        }

        subtitleIconView.snp.makeConstraints {
            $0.size.equalTo(12)
        }

        subtitleStackView.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(14)
            $0.trailing.lessThanOrEqualToSuperview().inset(14)
            $0.top.equalTo(amountContainerView.snp.bottom).offset(4)
        }

        statusView.snp.makeConstraints {
            $0.leading.greaterThanOrEqualToSuperview().offset(14)
            $0.trailing.equalToSuperview().inset(8)
            $0.top.equalTo(subtitleStackView.snp.bottom).offset(4)
            $0.bottom.equalToSuperview().inset(8)
        }
    }

    private func apply(_ any: UIContentConfiguration) {
        guard let configuration = any as? ChatTransferMessageConfiguration else { return }
        appliedConfiguration = configuration

        titleLabel.text = configuration.title
        receivedAmountLabel.text = configuration.amountText
        tokenSymbolLabel.text = configuration.tokenSymbol

        originalAmountLabel.textColor = configuration.originalAmountTextColor
        if let originalAmount = configuration.originalAmountText {
            let typography: TypographyStyle = .bodyMedium
            let spec = typography.resolvedSpec
            var attributes = LabelStyle(
                font: .app(typography),
                lineHeight: spec.lineHeight,
                tracking: spec.tracking
            ).attributes(for: .center)
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            originalAmountLabel.attributedText = NSAttributedString(
                string: originalAmount,
                attributes: attributes
            )
            originalAmountLabel.isHidden = false
            subtitleLabel.text = String(localized: .transferStatusAmountDiffers)
            subtitleLabel.textColor = .fgWarning
            subtitleIconView.isHidden = true
        } else {
            originalAmountLabel.attributedText = nil
            originalAmountLabel.isHidden = true
            subtitleLabel.text = configuration.state.title
            subtitleLabel.textColor = configuration.state.color
            subtitleIconView.isHidden = false
            subtitleIconView.image = configuration.state.icon
            subtitleIconView.tintColor = configuration.state.color
        }

        statusView.configuration = configuration.statusConfiguration

        receivedAmountLabel.textColor = configuration.amountTextColor
        amountContainerView.applyBackgroundStyle(configuration.amountBackgroundColor, cornerRadius: 12)
        titleLabel.textColor = configuration.titleColor

        bubbleView.fillColor = configuration.backgroundColor
        bubbleView.corners = ChatMessageContainerConfiguration.LayoutType.plain
            .cornerRadii(for: configuration.side)

        switch configuration.side {
        case .leading:
            bubbleLeadingConstraint?.isActive = true
            bubbleTrailingConstraint?.isActive = false
        case .trailing:
            bubbleLeadingConstraint?.isActive = false
            bubbleTrailingConstraint?.isActive = true
        }
    }
}

private extension ChatTransferMessageConfiguration.DirectionalState {
    var icon: UIImage? {
        switch self {
        case .incoming(.processing),
             .incoming(.sent),
             .incoming(.claiming),
             .incoming(.partiallyClaimed):
            UIImage(resource: .iconTransferIn)
        case .outgoing(.processing),
             .outgoing(.sent),
             .outgoing(.claiming),
             .outgoing(.partiallyClaimed):
            UIImage(resource: .iconTransferOut)
        case .incoming(.finished),
             .outgoing(.finished):
            UIImage(resource: .iconTransferDone)
        case .incoming(.error),
             .outgoing(.error):
            UIImage(resource: .iconTransferError)
        }
    }

    var color: UIColor {
        switch self {
        case .incoming(.error),
             .outgoing(.error):
            .fgError
        case .incoming:
            .fgSecondary
        case .outgoing:
            .fgSecondaryInverted
        }
    }

    var title: String {
        switch self {
        case let .incoming(state):
            state.incomingTitle
        case let .outgoing(state):
            state.outgoingTitle
        }
    }
}

private extension ChatTransferMessageConfiguration.State {
    var incomingTitle: String {
        switch self {
        case .processing:
            String(localized: .transferStatusDetecting)
        case .sent:
            String(localized: .transferStatusDetecting)
        case .claiming:
            String(localized: .transferStatusClaiming)
        case .partiallyClaimed:
            String(localized: .transferStatusPartiallyClaimed)
        case .finished:
            String(localized: .transferStatusFinished)
        case .error:
            String(localized: .transferStatusError)
        }
    }

    var outgoingTitle: String {
        switch self {
        case .processing:
            String(localized: .transferStatusSending)
        case .sent:
            String(localized: .transferStatusSent)
        case .claiming:
            String(localized: .transferStatusClaiming)
        case .partiallyClaimed:
            String(localized: .transferStatusPartiallyClaimed)
        case .finished:
            String(localized: .transferStatusFinished)
        case .error:
            String(localized: .transferStatusError)
        }
    }
}

// MARK: - AccessibilityBound

extension ChatTransferMessageView: AccessibilityBound {
    var accessibilityBindings: [AccessibilityBinding] {
        [
            .init(bubbleView, AccessibilityID.Chat.transferMessageBubble),
            .init(subtitleLabel, AccessibilityID.Chat.transferStatusLabel)
        ]
    }
}

#if DEBUG
    #Preview {
        let inbox = ChatTransferMessageConfiguration.inbox(
            amount: "17",
            tokenSymbol: "DOT",
            from: "Samuel.long.long.18",
            state: .processing,
            statusConfiguration: .init(
                dateFormatter: TimestampFormatter(),
                date: .now,
                textColor: .fgPrimary,
                image: nil,
                isEdited: false
            )
        ).makeContentView()

        let inbox2 = ChatTransferMessageConfiguration.inbox(
            amount: "17",
            tokenSymbol: "DOT",
            originalAmount: "55",
            from: "Samuel.long.18",
            state: .processing,
            statusConfiguration: .init(
                dateFormatter: TimestampFormatter(),
                date: .now,
                textColor: .fgPrimary,
                image: nil,
                isEdited: false
            )
        ).makeContentView()

        let outbox = ChatTransferMessageConfiguration.outbox(
            amount: "99999",
            tokenSymbol: "DOT",
            state: .sent,
            statusConfiguration: .init(
                dateFormatter: TimestampFormatter(),
                date: .now,
                textColor: .fgPrimaryInverted,
                image: nil,
                isEdited: false
            )
        ).makeContentView()

        let stack = UIStackView(arrangedSubviews: [inbox, inbox2, outbox])
        stack.axis = .vertical
        stack.spacing = 20
        stack.backgroundColor = .bgSurfaceMain
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins.top = 20
        stack.layoutMargins.bottom = 20
        return stack
    }
#endif
