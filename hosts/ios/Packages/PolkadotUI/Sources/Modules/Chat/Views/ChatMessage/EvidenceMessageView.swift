import UIKit
import DesignSystem
internal import UIKit_iOS
internal import SnapKit

public struct EvidenceMessageViewConfiguration: HashableContentConfiguration {
    let mediaConfiguration: ChatMessageMediaViewConfiguration
    let messageText: String
    let status: StatusModel
    let additionalMessageText: String?
    let actionHandler: (() -> Void)?

    public init(
        mediaConfiguration: ChatMessageMediaViewConfiguration,
        messageText: String,
        status: StatusModel,
        additionalMessageText: String?,
        actionHandler: (() -> Void)? = nil
    ) {
        self.mediaConfiguration = mediaConfiguration
        self.messageText = messageText
        self.status = status
        self.additionalMessageText = additionalMessageText
        self.actionHandler = actionHandler
    }

    public func makeContentView() -> any UIView & UIContentView {
        EvidenceMessageView(configuration: self)
    }

    public static func == (
        lhs: EvidenceMessageViewConfiguration,
        rhs: EvidenceMessageViewConfiguration
    ) -> Bool {
        lhs.mediaConfiguration == rhs.mediaConfiguration &&
            lhs.messageText == rhs.messageText &&
            lhs.status == rhs.status &&
            lhs.additionalMessageText == rhs.additionalMessageText
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(mediaConfiguration)
        hasher.combine(messageText)
        hasher.combine(status)
        hasher.combine(additionalMessageText)
    }
}

final class EvidenceMessageView: UIView, UIContentView {
    private let stackView: UIStackView = .create { view in
        view.axis = .vertical
        view.spacing = 16
        view.alignment = .center
    }

    private let mediaView = ChatMessageMediaView(configuration: .init())

    private let messageLabel: MarkdownLabel = .create { view in
        view.typography = .bodyMedium
        view.textColor = UIColor(resource: .textAndIconsSecondary)
        view.numberOfLines = 0
        view.textAlignment = .center
    }

    private let statusIconView: UIImageView = .create { view in
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private let statusLabel: Label = .create { view in
        view.typography = .bodyMedium
        view.numberOfLines = 1
    }

    private let statusStack: UIStackView = .create { view in
        view.axis = .horizontal
        view.spacing = 4
        view.alignment = .center
    }

    private let infoRowStack: UIStackView = .create { view in
        view.axis = .horizontal
        view.spacing = 8
        view.alignment = .center
    }

    private let actionButton: RoundedButton = .create { view in
        view.applySecondaryStyle(titleFont: UIFont.titleSmall)
        view.contentInsets = UIEdgeInsets(top: 12, left: 32, bottom: 12, right: 32)
        view.setHidden(true)
    }

    private let additionalMessageLabel: MarkdownLabel = .create { view in
        view.typography = .bodyMedium
        view.textColor = UIColor(resource: .textAndIconsSecondary)
        view.numberOfLines = 0
        view.textAlignment = .center
    }

    private let additionalMessageContainer = UIView()

    private var appliedConfiguration: EvidenceMessageViewConfiguration
    private var actionHandler: (() -> Void)?

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set { apply(newValue) }
    }

    init(configuration: EvidenceMessageViewConfiguration) {
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
        addSubview(stackView)
        stackView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalToSuperview().offset(16)
            $0.bottom.equalToSuperview().inset(16)
        }

        statusStack.addArrangedSubview(statusIconView)
        statusStack.addArrangedSubview(statusLabel)

        infoRowStack.addArrangedSubview(messageLabel)
        infoRowStack.addArrangedSubview(statusStack)

        actionButton.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        actionButton.addTarget(self, action: #selector(handleActionButton), for: .touchUpInside)

        additionalMessageContainer.addSubview(additionalMessageLabel)
        additionalMessageLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(36)
            make.top.bottom.equalToSuperview()
        }

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.addArrangedSubview(UIView()) // spacer
        hStack.addArrangedSubview(mediaView)

        stackView.addArrangedSubview(hStack)
        stackView.addArrangedSubview(infoRowStack)
        stackView.addArrangedSubview(additionalMessageContainer)
        stackView.addArrangedSubview(actionButton)

        mediaView.snp.makeConstraints {
            $0.width.equalToSuperview().multipliedBy(0.88)
            $0.width.equalTo(mediaView.snp.height)
        }
    }

    private func apply(_ any: UIContentConfiguration) {
        guard let configuration = any as? EvidenceMessageViewConfiguration else { return }
        appliedConfiguration = configuration
        actionHandler = configuration.actionHandler

        mediaView.configuration = configuration.mediaConfiguration

        messageLabel.text = configuration.messageText

        statusLabel.text = configuration.status.text
        statusLabel.textColor = configuration.status.color
        statusIconView.image = configuration.status.image.withRenderingMode(.alwaysTemplate)
        statusIconView.tintColor = configuration.status.color

        if let action = configuration.status.action {
            actionButton.setTitle(action.title)
            actionButton.setHidden(false)
        } else {
            actionButton.setHidden(true)
        }

        if let additionalMessageText = configuration.additionalMessageText {
            additionalMessageLabel.text = additionalMessageText
            additionalMessageContainer.setHidden(false)
        } else {
            additionalMessageContainer.setHidden(true)
        }
    }

    @objc private func handleActionButton() {
        appliedConfiguration.status.action?.handler()
    }
}

public extension EvidenceMessageViewConfiguration {
    struct StatusModel: Equatable, Hashable {
        let text: String
        let image: UIImage
        let color: UIColor
        var action: ActionConfiguration?

        public init(
            text: String,
            image: UIImage,
            color: UIColor,
            action: ActionConfiguration? = nil
        ) {
            self.text = text
            self.image = image
            self.color = color
            self.action = action
        }
    }

    struct ActionConfiguration: Hashable {
        let title: String
        let handler: () -> Void

        public init(title: String, handler: @escaping () -> Void = {}) {
            self.title = title
            self.handler = handler
        }

        public static func == (
            lhs: ActionConfiguration,
            rhs: ActionConfiguration
        ) -> Bool {
            lhs.title == rhs.title
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(title)
        }
    }
}

public extension EvidenceMessageViewConfiguration.StatusModel {
    static func queued() -> Self {
        .init(
            text: String(localized: .chatEvidenceUploadQueued),
            image: UIImage(resource: .upload),
            color: UIColor(resource: .textAndIconsSecondary)
        )
    }

    static func uploading() -> Self {
        .init(
            text: String(localized: .chatEvidenceUploading),
            image: UIImage(resource: .upload),
            color: UIColor(resource: .textAndIconsSecondary)
        )
    }

    static func uploadFailed(action: @escaping () -> Void) -> Self {
        .init(
            text: String(localized: .chatEvidenceUploadFailed),
            image: UIImage(resource: .messageSent),
            color: .fgError,
            action: .init(title: String(localized: .chatEvidenceRetry), handler: action)
        )
    }

    static func inReview() -> Self {
        .init(
            text: String(localized: .chatEvidenceInReview),
            image: UIImage(resource: .voting),
            color: .fgWarning
        )
    }

    static func approved() -> Self {
        .init(
            text: String(localized: .chatEvidenceApproved),
            image: UIImage(resource: .messageSent),
            color: .fgSuccess
        )
    }
}

#if DEBUG
    #Preview("Upload Failed") {
        EvidenceMessageViewConfiguration(
            mediaConfiguration: ChatMessageMediaViewConfiguration(
                status: .mediaUploadFailed(),
                deliveryDetails: .mediaUploadFailed(),
                buttonConfiguration: .init(style: .retry)
            ),
            messageText: "1234",
            status: .uploadFailed(action: {}),
            additionalMessageText: nil
        )
        .makeContentView()
    }

    #Preview("In Review") {
        EvidenceMessageViewConfiguration(
            mediaConfiguration: ChatMessageMediaViewConfiguration(
                status: nil,
                deliveryDetails: nil
            ),
            messageText: String(localized: .chatEvidenceMessagePhoto),
            status: .inReview(),
            additionalMessageText: nil
        )
        .makeContentView()
    }
#endif
