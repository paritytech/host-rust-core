import SwiftUI
import UIKit
import DesignSystem
internal import SnapKit

public protocol TattooNameProviding: AnyObject {
    var identifier: String { get }

    func provideName(_ completion: @escaping (String?) -> Void)
    func cancel()
}

public struct TattooCommitmentMessageViewConfiguration: HashableContentConfiguration {
    let mediaConfiguration: ChatMessageMediaViewConfiguration
    let tattooNameProvider: TattooNameProviding?

    public init(
        mediaConfiguration: ChatMessageMediaViewConfiguration,
        tattooNameProvider: TattooNameProviding? = nil
    ) {
        self.mediaConfiguration = mediaConfiguration
        self.tattooNameProvider = tattooNameProvider
    }

    public func makeContentView() -> any UIView & UIContentView {
        TattooCommitmentMessageView(configuration: self)
    }

    public func updated(for _: UIConfigurationState) -> Self { self }

    public static func == (
        lhs: TattooCommitmentMessageViewConfiguration,
        rhs: TattooCommitmentMessageViewConfiguration
    ) -> Bool {
        lhs.mediaConfiguration == rhs.mediaConfiguration &&
            lhs.tattooNameProvider?.identifier == rhs.tattooNameProvider?.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(mediaConfiguration)
        hasher.combine(tattooNameProvider?.identifier)
    }
}

final class TattooCommitmentMessageView: UIView, UIContentView {
    private let stackView: UIStackView = .create { view in
        view.axis = .vertical
        view.spacing = 24
        view.alignment = .fill
    }

    private let messageLabel: MarkdownLabel = .create { view in
        view.typography = .bodyMedium
        view.textColor = UIColor(resource: .textAndIconsSecondary)
        view.numberOfLines = 0
        view.textAlignment = .center
    }

    private let mediaView = ChatMessageMediaView(configuration: .init())

    private var appliedConfiguration: TattooCommitmentMessageViewConfiguration

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set { apply(newValue) }
    }

    init(configuration: TattooCommitmentMessageViewConfiguration) {
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
            $0.leading.trailing.bottom.equalToSuperview()
            $0.top.equalToSuperview().offset(16)
        }

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.addArrangedSubview(UIView()) // spacer
        hStack.addArrangedSubview(mediaView)

        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(hStack)

        mediaView.snp.makeConstraints {
            $0.width.equalToSuperview().multipliedBy(0.88)
            $0.width.equalTo(mediaView.snp.height)
        }
    }

    private func apply(_ any: UIContentConfiguration) {
        guard let configuration = any as? TattooCommitmentMessageViewConfiguration else { return }

        // Cancel previous provider if different
        if appliedConfiguration.tattooNameProvider?.identifier !=
            configuration.tattooNameProvider?.identifier {
            appliedConfiguration.tattooNameProvider?.cancel()
        }

        appliedConfiguration = configuration

        messageLabel.setText(markdown: String(localized: .messageCommitPreview))

        mediaView.configuration = configuration.mediaConfiguration
        updateNameIfNeeded()
    }

    private func updateNameIfNeeded() {
        guard let provider = appliedConfiguration.tattooNameProvider else { return }

        provider.provideName { [weak self, weak provider] name in
            guard let name,
                  let self,
                  let provider,
                  let currentProviderId = appliedConfiguration.tattooNameProvider?.identifier,
                  currentProviderId == provider.identifier else {
                return
            }
            let messageText = String(localized: .messageCommitTattoo(name: name))
            messageLabel.setText(markdown: messageText)
        }
    }
}

#if DEBUG
    #Preview(traits: .fixedLayout(width: 320, height: 280)) {
        TattooCommitmentMessageViewConfiguration(
            mediaConfiguration: ChatMessageMediaViewConfiguration(
                previewBackgroundColor: UIColor(resource: .white100)
            )
        )
        .makeContentView()
    }
#endif
