import Foundation
import UIKit
import DesignSystem
internal import SnapKit
internal import UIKit_iOS

final class MobRuleMessageView: UIView, UIContentView {
    private lazy var videoMedia = ChatMessageMediaView(configuration: .init())
    private lazy var photoMedia = ChatMessageMediaView(configuration: .init())

    private static let videoMediaBorderWidth: CGFloat = 2

    private let videoMediaOuterBorderView: UIView = create {
        $0.backgroundColor = .clear
        $0.isUserInteractionEnabled = false
        $0.layer.cornerRadius = 7 // picked by trying different values
        $0.layer.borderWidth = videoMediaBorderWidth
        $0.layer.borderColor = UIColor.strokePrimary.cgColor
    }

    private let typeLabel: Label = create {
        $0.typography = .paragraphLarge
        $0.textColor = .fgPrimary
    }

    private let descriptionLabel: MarkdownLabel = create {
        $0.typography = .paragraphLarge
        $0.textColor = .fgPrimary
        $0.numberOfLines = 0
    }

    private let toggleExpansionButton: RoundedButton = create {
        $0.applyTitleTertiaryStyle()
        $0.imageWithTitleView?.titleFont = UIFont.paragraphLarge
        $0.transform.ty = 1
        $0.contentInsets = .zero
    }

    private let viewCaseButton: RoundedButton = create {
        $0.applyTitleTertiaryStyle()
        $0.contentInsets = .init(top: 12, left: 0, bottom: 12, right: 0)
    }

    private let negativeVoteButton: LoadableRoundedButton = create {
        $0.contentView.applySecondaryStyle()
        $0.contentView.imageWithTitleView?.titleColor = UIColor(resource: .systemError)
        $0.contentView.setTitle(String(localized: .mobRuleVoteFalse))
        $0.contentView.setIcon(UIImage(resource: .falseAction))
        $0.contentView.contentInsets = .init(top: 8, left: 0, bottom: 8, right: 0)
    }

    private let positiveVoteButton: LoadableRoundedButton = create {
        $0.contentView.applySecondaryStyle()
        $0.contentView.imageWithTitleView?.titleColor = UIColor(resource: .systemSuccess)
        $0.contentView.setTitle(String(localized: .mobRuleVoteTrue))
        $0.contentView.setIcon(UIImage(resource: .trueAction))
        $0.contentView.contentInsets = .init(top: 8, left: 0, bottom: 8, right: 0)
    }

    private let sensitiveContentAllowButton: LoadableRoundedButton = create {
        $0.contentView.applySecondaryStyle()
        $0.contentView.setTitle(String(localized: .mobRuleSensitiveContentViewAndJudge))
        $0.contentView.contentInsets = .init(top: 12, left: 0, bottom: 12, right: 0)
    }

    private let sensitiveContentSkipButton: LoadableRoundedButton = create {
        $0.contentView.applySecondaryStyle()
        $0.contentView.setTitle(String(localized: .mobRuleSensitiveContentSkipEvidence))
        $0.contentView.contentInsets = .init(top: 12, left: 0, bottom: 12, right: 0)
    }

    var sensitiveOverlayView: SensitiveContentOverlayView?

    // plain: media
    // compact: media + typeLabel
    let topContainerHStackView = UIStackView()

    let mediaHStack = UIStackView()

    // expanded: VStack typeLabel, descriptionLabel, toggleExpansionButton
    // collapsed: HStack typeLabel, toggleExpansionButton
    let detailsStackView = UIStackView()

    // separator + viewCase button
    let viewCaseStack = UIStackView()

    let actionsStack = UIStackView()

    let sensitiveActionsStack = UIStackView()

    var plainConstraints: [Constraint] = []
    var compactConstraints: [Constraint] = []

    private var appliedConfiguration: MobRuleMessageConfiguration
    // Used for optimisation
    // Avoid alpha animation if configuration updated but expansion remains the same
    private var isExpanded: Bool?

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set { apply(newValue) }
    }

    override var intrinsicContentSize: CGSize {
        UIView.layoutFittingCompressedSize
    }

    init(configuration: MobRuleMessageConfiguration) {
        appliedConfiguration = configuration
        super.init(frame: .zero)
        setupViews()
        setupHandlers()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Top part
        topContainerHStackView.alignment = .center

        topContainerHStackView.isLayoutMarginsRelativeArrangement = true
        topContainerHStackView.spacing = 8
        topContainerHStackView.addArrangedSubview(mediaHStack)

        mediaHStack.layer.borderColor = UIColor.strokePrimary.cgColor
        mediaHStack.axis = .horizontal
        mediaHStack.distribution = .fillEqually
        mediaHStack.addArrangedSubview(videoMedia)
        mediaHStack.addArrangedSubview(photoMedia)

        videoMedia.addSubview(videoMediaOuterBorderView)
        videoMediaOuterBorderView.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(-Self.videoMediaBorderWidth)
        }

        // Middle Part
        detailsStackView.spacing = 8
        detailsStackView.isLayoutMarginsRelativeArrangement = true
        detailsStackView.layoutMargins = .init(top: 14, left: 14, bottom: 14, right: 14)

        // it is expected here in .plain layout
        // detailsStackView.addArrangedSubview(typeLabel)
        detailsStackView.addArrangedSubview(descriptionLabel)
        detailsStackView.addArrangedSubview(toggleExpansionButton)
        detailsStackView.addArrangedSubview(UIView()) // spacer

        // Bottom Part
        viewCaseStack.axis = .vertical
        viewCaseStack.isLayoutMarginsRelativeArrangement = true
        viewCaseStack.layoutMargins = .init(top: 0, left: 14, bottom: 0, right: 14)
        let separatorView = SeparatorContentConfiguration(
            color: .strokePrimary,
            height: 1,
            insets: .init(horizontal: 0)
        ).makeContentView()

        viewCaseStack.addArrangedSubview(separatorView)
        viewCaseStack.addArrangedSubview(viewCaseButton)

        // Actions Part
        actionsStack.distribution = .fillEqually
        actionsStack.spacing = 4

        // Global Part
        let roundedContainerVStack = UIStackView()
        roundedContainerVStack.axis = .vertical
        roundedContainerVStack.backgroundColor = .bgSurfaceContainer
        roundedContainerVStack.layer.cornerRadius = 16

        roundedContainerVStack.addArrangedSubview(topContainerHStackView)
        roundedContainerVStack.addArrangedSubview(detailsStackView)
        roundedContainerVStack.addArrangedSubview(viewCaseStack)

        let mainVStack = UIStackView()
        mainVStack.spacing = 4
        mainVStack.axis = .vertical
        mainVStack.addArrangedSubview(roundedContainerVStack)
        mainVStack.addArrangedSubview(actionsStack)

        addSubview(mainVStack)
        mainVStack.snp.makeConstraints {
            $0.width.greaterThanOrEqualToSuperview().multipliedBy(0.85)
            $0.width.lessThanOrEqualToSuperview().multipliedBy(0.9)
            $0.verticalEdges.equalToSuperview()
            $0.leading.equalToSuperview()
        }

        topContainerHStackView.snp.makeConstraints {
            $0.width.equalToSuperview()
        }

        videoMedia.snp.makeConstraints {
            $0.width.equalTo(videoMedia.snp.height)
        }

        photoMedia.snp.makeConstraints {
            $0.width.equalTo(photoMedia.snp.height)
        }

        compactConstraints += videoMedia.snp.prepareConstraints {
            $0.height.equalTo(16)
        }

        compactConstraints += photoMedia.snp.prepareConstraints {
            $0.height.equalTo(16)
        }
    }

    private func setupHandlers() {
        toggleExpansionButton.addTarget(self, action: #selector(toggleExpansion), for: .touchUpInside)
        viewCaseButton.addTarget(self, action: #selector(viewCasePressed), for: .touchUpInside)

        negativeVoteButton.contentView.addTarget(self, action: #selector(negativeVotePressed), for: .touchUpInside)
        positiveVoteButton.contentView.addTarget(self, action: #selector(positiveVotePressed), for: .touchUpInside)

        sensitiveContentSkipButton.contentView.addTarget(self, action: #selector(skipCasePressed), for: .touchUpInside)
        sensitiveContentAllowButton.contentView.addTarget(
            self,
            action: #selector(viewAndJudgePressed),
            for: .touchUpInside
        )
    }

    private func apply(_ any: UIContentConfiguration) {
        guard let configuration = any as? MobRuleMessageConfiguration else { return }
        appliedConfiguration = configuration

        applyLayout()
        applyMedia()

        typeLabel.text = configuration.type
        descriptionLabel.text = configuration.details
    }
}

private extension MobRuleMessageView {
    func applyLayout() {
        switch appliedConfiguration.layout {
        case .plain:
            // remove
            topContainerHStackView.removeArrangedSubview(typeLabel)
            typeLabel.removeFromSuperview()
            // add
            detailsStackView.insertArrangedSubview(typeLabel, at: 0)
            // update constraints
            compactConstraints.forEach { $0.deactivate() }
            plainConstraints.forEach { $0.activate() }

            topContainerHStackView.layoutMargins = .init(top: 2, left: 2, bottom: 0, right: 2)

            detailsStackView.setHidden(false)
            detailsStackView.alpha = 1

            mediaHStack.spacing = 2
            videoMediaOuterBorderView.setHidden(true)

            viewCaseStack.setHidden(true)
            viewCaseStack.alpha = 0
        case .compact:
            detailsStackView.removeArrangedSubview(typeLabel)
            typeLabel.removeFromSuperview()

            topContainerHStackView.addArrangedSubview(typeLabel)

            plainConstraints.forEach { $0.deactivate() }
            compactConstraints.forEach { $0.activate() }

            topContainerHStackView.layoutMargins = .init(top: 12, left: 14, bottom: 12, right: 14)

            detailsStackView.setHidden(true)
            detailsStackView.alpha = 0

            mediaHStack.spacing = -2
            mediaHStack.sendSubviewToBack(photoMedia)
            videoMediaOuterBorderView.setHidden(false)

            viewCaseStack.setHidden(false)
            viewCaseStack.alpha = 1
        }

        applyActions()
        applySensitivity()
        applyArchivedState()
        applyExpansion()
    }

    func applyActions() {
        switch appliedConfiguration.actionType {
        case let .vote(positiveAction, negativeAction):
            actionsStack.setHidden(false)
            actionsStack.arrangedSubviews.forEach {
                actionsStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            actionsStack.axis = .horizontal
            actionsStack.addArrangedSubview(negativeVoteButton)
            actionsStack.addArrangedSubview(positiveVoteButton)

            apply(configuration: negativeAction, for: negativeVoteButton)
            apply(configuration: positiveAction, for: positiveVoteButton)
        case let .sensitiveContent(viewAction, skipAction):
            actionsStack.setHidden(false)
            actionsStack.arrangedSubviews.forEach {
                actionsStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            actionsStack.axis = .vertical
            actionsStack.addArrangedSubview(sensitiveContentAllowButton)
            actionsStack.addArrangedSubview(sensitiveContentSkipButton)

            apply(configuration: viewAction, for: sensitiveContentAllowButton)
            apply(configuration: skipAction, for: sensitiveContentSkipButton)
        case .none:
            actionsStack.setHidden(true)
        }
    }

    func applySensitivity() {
        if appliedConfiguration.isSensitive,
           !appliedConfiguration.isCompact {
            guard sensitiveOverlayView == nil else {
                return
            }
            let cornerRadius: CGFloat = 16
            let overlay = SensitiveContentOverlayView()
            overlay.layer.cornerRadius = cornerRadius
            sensitiveOverlayView = overlay

            mediaHStack.addSubview(overlay)
            overlay.snp.makeConstraints {
                $0.directionalEdges.equalToSuperview()
            }

            mediaHStack.arrangedSubviews.forEach {
                $0.layer.cornerRadius = cornerRadius
                $0.clipsToBounds = true
            }
        } else {
            mediaHStack.arrangedSubviews.forEach {
                $0.layer.cornerRadius = .zero
                $0.clipsToBounds = false
            }

            sensitiveOverlayView?.removeFromSuperview()
            sensitiveOverlayView = nil
        }
    }

    func applyArchivedState() {
        if !appliedConfiguration.isArchived {
            viewCaseButton.setTitle(String(localized: .mobRuleCaseViewCase))
            viewCaseButton.isEnabled = true
        } else {
            viewCaseButton.setTitle(String(localized: .mobRuleCaseArchived))
            viewCaseButton.isEnabled = false
        }
    }

    func applyMedia() {
        let handleMediaTap: () -> Void = { [weak self] in
            self?.handleMediaTap()
        }

        if case let .compact(configuration) = appliedConfiguration.layout,
           configuration.isSensitive {
            videoMedia.setHidden(true)
            // static image (sensitiveContent)
            photoMedia.configuration = ChatMessageMediaViewConfiguration(
                previewProvider: StaticImagePreviewProvider(image: UIImage(resource: .sensitiveContent)),
                corners: .zero,
                tapOnMedia: handleMediaTap
            )
            return
        }

        let corners =
            switch appliedConfiguration.layout {
            case .compact: CornersConfiguration.compactMobRuleMedia
            case .plain: CornersConfiguration.mobRuleMedia
            }

        let videoButtonConfiguration: ChatMessageMediaViewConfiguration
            .ButtonConfiguration? =
                if appliedConfiguration.showPlayButton, case .plain = appliedConfiguration.layout {
                    .init(
                        style: .play,
                        size: .compact,
                        action: handleMediaTap
                    )
                } else {
                    nil
                }

        videoMedia.setHidden(false)
        videoMedia.configuration = ChatMessageMediaViewConfiguration(
            previewProvider: appliedConfiguration.mediaPreviewProvider,
            corners: corners,
            buttonConfigurationProvider: videoButtonConfiguration?.asProvider(),
            tapOnMedia: handleMediaTap
        )

        photoMedia.configuration = ChatMessageMediaViewConfiguration(
            previewProvider: appliedConfiguration.tattooPreviewProvider,
            previewBackgroundColor: UIColor(resource: .white100),
            corners: corners,
            tapOnMedia: handleMediaTap
        )
    }

    func applyExpansion() {
        guard let isExpanded = appliedConfiguration.isExpanded,
              self.isExpanded != isExpanded else {
            return
        }

        self.isExpanded = isExpanded

        let shouldBeAnimated = detailsStackView.bounds.size != .zero

        if shouldBeAnimated {
            applyExpansion(expanded: isExpanded)
            descriptionLabel.alpha = 0
            UIView.animate(withDuration: 0.2) { [self] in
                layoutIfNeeded()
            } completion: { _ in
                UIView.animate(withDuration: 0.1) { [self] in
                    descriptionLabel.alpha = 1
                }
            }
        } else {
            applyExpansion(expanded: isExpanded)
        }
    }

    func applyExpansion(expanded: Bool) {
        if expanded {
            detailsStackView.axis = .vertical
            detailsStackView.alignment = .leading
            descriptionLabel.setHidden(false)
            toggleExpansionButton.setTitle(String(localized: .mobRuleDetailsShowLess))
        } else {
            detailsStackView.axis = .horizontal
            detailsStackView.alignment = .fill
            descriptionLabel.setHidden(true)
            toggleExpansionButton.setTitle(String(localized: .mobRuleDetailsShowMore))
        }
    }

    func apply(configuration: MobRuleMessageConfiguration.ActionConfiguration, for button: LoadableRoundedButton) {
        if configuration.inProgress {
            button.startLoading()
        } else {
            button.stopLoading()
            button.contentView.isEnabled = configuration.isEnabled
        }
    }

    @objc func handleMediaTap() {
        appliedConfiguration.activityHandler?(.showEvidence)
    }

    @objc private func toggleExpansion() {
        guard let state = appliedConfiguration.isExpanded else { return }
        appliedConfiguration.activityHandler?(.toggleExpansion(isExpanded: state))
    }

    @objc private func positiveVotePressed() {
        appliedConfiguration.activityHandler?(.vote(isPositive: true))
    }

    @objc private func negativeVotePressed() {
        appliedConfiguration.activityHandler?(.vote(isPositive: false))
    }

    @objc private func viewAndJudgePressed() {
        appliedConfiguration.activityHandler?(.viewAndJudge)
    }

    @objc private func skipCasePressed() {
        appliedConfiguration.activityHandler?(.skipCase)
    }

    @objc private func viewCasePressed() {
        appliedConfiguration.activityHandler?(.viewCase)
    }
}

extension MobRuleMessageView {}

#if DEBUG
    let duration: TimeInterval = 1
    var delay: TimeInterval = duration
    func scheduleUpdate(configuration: UIContentConfiguration, view: any (UIView & UIContentView)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIView.animate(withDuration: duration) {
                view.configuration = configuration
            }
        }

        delay += duration
    }

    #Preview("Collapse / Expand") {
        let view = MobRuleMessageConfiguration
            .expandedVoting()
            .makeContentView()

        scheduleUpdate(
            configuration: MobRuleMessageConfiguration.collapsedVoting(),
            view: view
        )

        scheduleUpdate(
            configuration: MobRuleMessageConfiguration.expandedVoting(),
            view: view
        )

        return view
    }

    #Preview("Compact / Plain") {
        let view = MobRuleMessageConfiguration
            .compact()
            .makeContentView()

        scheduleUpdate(
            configuration: MobRuleMessageConfiguration.expandedVoting(),
            view: view
        )

        scheduleUpdate(
            configuration: MobRuleMessageConfiguration.compact(),
            view: view
        )

        return view
    }
#endif
