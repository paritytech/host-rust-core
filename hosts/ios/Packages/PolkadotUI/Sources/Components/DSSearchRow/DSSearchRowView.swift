import DesignSystem
import ExternalAccessibility
import UIKit
internal import SnapKit
internal import UIKit_iOS

/// Search row for the scan panel: an edge-to-edge capsule with a close button shown only while editing.
public final class DSSearchRowView: UIView {
    private let searchCapsuleContainer = {
        let view = DSChatInputGlassBackground(
            cornerRadius: 24,
            fallbackColor: .bgSurfaceContainer,
            interactive: false
        )
        view.snp.makeConstraints {
            $0.height.equalTo(48)
        }

        return view
    }()

    let searchImageView: UIImageView = create {
        $0.image = UIImage(resource: .search18).withRenderingMode(.alwaysTemplate)
        $0.tintColor = UIColor.fgSecondary
        $0.snp.makeConstraints {
            $0.width.height.equalTo(18)
        }
    }

    public let searchField: UITextField = create {
        var defaultTextAttributes = LabelStyle.body14Regular().attributes()
        defaultTextAttributes[.foregroundColor] = UIColor.fgPrimary

        var placeholderAttributes = defaultTextAttributes
        placeholderAttributes[.foregroundColor] = UIColor.fgDisabled

        $0.defaultTextAttributes = defaultTextAttributes
        $0.attributedPlaceholder = NSAttributedString(
            string: String(localized: .searchContactFieldPlaceholder),
            attributes: placeholderAttributes
        )

        $0.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        $0.autocapitalizationType = .none
        $0.autocorrectionType = .no
        $0.textContentType = .nickname
        $0.smartQuotesType = .no
        $0.smartDashesType = .no
        $0.spellCheckingType = .no

        $0.tintColor = UIColor.fgPrimary
    }

    public var searchHandler: ((String?) -> Void)?
    public var cancelHandler: (() -> Void)?

    private var cancelLeadingConstraint: Constraint?
    private var capsuleTrailingConstraint: Constraint?

    private let cancelButton = DSIconButton(
        style: .secondary,
        shape: .pill,
        size: .mediumIncreased,
        icon: UIImage(resource: .buttonClose),
        glass: true
    )

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupHandlers()
        applyAccessibilityBindings()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Controls whether the Cancel control is visible (shown only while the field is edited).
    /// When visible, the search capsule stops before the button; when hidden, it stretches
    /// to fill the row's width.
    public func setCancelVisible(_ visible: Bool) {
        cancelButton.isHidden = !visible

        if visible {
            capsuleTrailingConstraint?.deactivate()
            cancelLeadingConstraint?.activate()
        } else {
            cancelLeadingConstraint?.deactivate()
            capsuleTrailingConstraint?.activate()
        }
    }

    private func setupViews() {
        addSubview(searchCapsuleContainer)
        addSubview(cancelButton)

        searchCapsuleContainer.snp.makeConstraints {
            $0.leading.equalToSuperview()
            $0.top.equalToSuperview().offset(8)
            $0.bottom.equalToSuperview().inset(8)
        }

        cancelButton.snp.makeConstraints {
            cancelLeadingConstraint = $0.leading.equalTo(searchCapsuleContainer.snp.trailing)
                .offset(DSSpacings.small).constraint
            // Square to the capsule's height so the pill stays circular; the leading and trailing
            // pins alone would leave the width to hugging priorities.
            $0.centerY.equalTo(searchCapsuleContainer)
            $0.width.height.equalTo(searchCapsuleContainer.snp.height)
            $0.trailing.equalToSuperview()
        }

        searchCapsuleContainer.snp.makeConstraints {
            capsuleTrailingConstraint = $0.trailing.equalToSuperview().constraint
        }
        capsuleTrailingConstraint?.deactivate()

        searchCapsuleContainer.addSubview(searchImageView)
        searchCapsuleContainer.addSubview(searchField)

        searchImageView.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(12)
            $0.centerY.equalToSuperview()
        }

        searchField.snp.makeConstraints {
            $0.leading.equalTo(searchImageView.snp.trailing).offset(8)
            $0.centerY.equalToSuperview()
            $0.trailing.equalToSuperview().inset(16)
        }
    }

    private func setupHandlers() {
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        cancelButton.onTap = { [weak self] in
            self?.cancelHandler?()
        }
    }

    @objc private func searchChanged() {
        searchHandler?(searchField.text)
    }
}

// MARK: - AccessibilityBound

extension DSSearchRowView: AccessibilityBound {
    public var accessibilityBindings: [AccessibilityBinding] {
        [
            .init(searchField, AccessibilityID.Chats.newChatUsernameInput),
            .init(cancelButton, AccessibilityID.Chats.newChatCancelButton)
        ]
    }
}
