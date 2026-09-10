import AVKit
import UIKit
import DesignSystem
internal import UIKit_iOS
internal import SnapKit

public protocol ProofOfInkVotingLayoutDelegate: AnyObject {
    func proofOfInkVotingLayoutDidTapClose(_ layout: ProofOfInkVotingLayout)
    func proofOfInkVotingLayoutDidTapReport(_ layout: ProofOfInkVotingLayout)
    func proofOfInkVotingLayoutDidVote(_ layout: ProofOfInkVotingLayout, result: ProofOfInkVotingLayout.VoteResult)
}

public final class ProofOfInkVotingLayout: UIView {
    public enum VoteResult {
        case positive
        case negative
    }

    // MARK: - Header

    public let closeButton: UIButton = create {
        $0.setImage(UIImage(resource: .buttonClose), for: .normal)
        $0.tintColor = UIColor(resource: .textAndIconsPrimaryDark)
    }

    private let titleLabel: Label = .create {
        $0.typography = .titleMedium
        $0.textColor = UIColor(resource: .textAndIconsPrimaryDark)
        $0.textAlignment = .center
    }

    private let subtitleLabel: Label = .create {
        $0.typography = .paragraphSmall
        $0.textColor = UIColor(resource: .textAndIconsSecondary)
        $0.textAlignment = .center
    }

    private let headerTitleStack: UIStackView = create {
        $0.axis = .vertical
        $0.alignment = .center
        $0.spacing = 2
    }

    public let reportButton: UIButton = create {
        $0.setImage(UIImage(resource: .flag), for: .normal)
        $0.tintColor = UIColor(resource: .textAndIconsPrimaryDark)

        // TODO: Implement report action logic + skip reported in MobRule widget
        // hidden temporary
        $0.setHidden(true)
    }

    // MARK: - Main Content Area

    private let mainContentContainer: UIView = create {
        $0.backgroundColor = UIColor(resource: .backgroundTertiary)
        $0.clipsToBounds = true
    }

    private let tattooContentImageView: UIImageView = .create {
        $0.backgroundColor = UIColor(resource: .white100)
        $0.contentMode = .scaleAspectFill
        $0.clipsToBounds = true
    }

    private var playerViewController: AVPlayerViewController?

    // MARK: - Preview Thumbnails

    private let mediaPreviewContainer: UIView = create {
        $0.layer.cornerRadius = 6
        $0.clipsToBounds = true
        $0.layer.borderWidth = 2
        $0.layer.borderColor = UIColor(resource: .textAndIconsPrimaryDark).cgColor
        $0.backgroundColor = UIColor(resource: .backgroundTertiary)
    }

    private let mediaPreviewImageView: UIImageView = .create {
        $0.contentMode = .scaleAspectFill
        $0.clipsToBounds = true
    }

    private let tattooPreviewContainer: UIView = create {
        $0.layer.cornerRadius = 6
        $0.clipsToBounds = true
        $0.layer.borderWidth = 2
        // Selection not visible with White background
        $0.layer.borderColor = UIColor(resource: .textAndIconsPrimaryDark).cgColor
        $0.backgroundColor = UIColor(resource: .white100)
    }

    private let tattooPreviewImageView: UIImageView = .create {
        $0.contentMode = .scaleAspectFill
        $0.clipsToBounds = true
    }

    private let previewStack: UIStackView = create {
        $0.axis = .horizontal
        $0.spacing = 16
        $0.alignment = .center
        $0.distribution = .fill
    }

    // MARK: - Voting Buttons

    let buttonsContainer: UIView = create {
        $0.backgroundColor = UIColor(resource: .fill8)
    }

    // TODO: use title image from mobrule assets
    let voteFalseButton: RoundedButton = .create {
        $0.applySecondaryStyle()
        $0.setTitle(String(localized: .mobRuleVoteFalse))
        $0.setIcon(UIImage(resource: .falseAction))
        $0.imageWithTitleView?.titleColor = UIColor(resource: .systemError)
        $0.snp.makeConstraints {
            $0.height.equalTo(44)
        }
        $0.roundedBackgroundView?.cornerRadius = 22
    }

    let voteTrueButton: RoundedButton = .create {
        $0.applySecondaryStyle()
        $0.setTitle(String(localized: .mobRuleVoteTrue))
        $0.setIcon(UIImage(resource: .trueAction))
        $0.imageWithTitleView?.titleColor = UIColor(resource: .systemSuccess)
        $0.snp.makeConstraints {
            $0.height.equalTo(44)
        }
        $0.roundedBackgroundView?.cornerRadius = 22
    }

    // MARK: - State

    private var isEvidenceSelected = true
    private var viewModel: ProofOfInkVotingViewModel?
    private weak var parentViewController: UIViewController?

    private var photoProvider: ChatMessageMediaPreviewProviding? {
        guard case let .photo(provider) = viewModel?.evidence else { return nil }
        return provider
    }

    public weak var delegate: ProofOfInkVotingLayoutDelegate?

    // MARK: - Init

    override public init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(resource: .backgroundPrimary)
        setupLayout()
        setupActions()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        performSizeBasedUpdates()
    }

    // MARK: - Public

    public func setParentViewController(_ viewController: UIViewController) {
        parentViewController = viewController
    }

    public func bind(viewModel: ProofOfInkVotingViewModel) {
        self.viewModel = viewModel

        titleLabel.text = viewModel.title
        subtitleLabel.text = viewModel.subtitle

        setVotingEnabled(viewModel.votingAvailable)

        // Load tattoo preview image
        viewModel.tattooProvider?.providePreview(
            for: tattooPreviewImageView,
            size: nil
        )

        // Setup main content based on evidence type
        setupEvidence(viewModel.evidence)

        // Start with media selected
        selectMediaPreview()
    }

    public func setVotingEnabled(_ enabled: Bool) {
        voteTrueButton.isEnabled = enabled
        voteFalseButton.isEnabled = enabled

        buttonsContainer.setHidden(!enabled)
    }
}

// MARK: - Media Setup

private extension ProofOfInkVotingLayout {
    func setupEvidence(_ evidence: ProofOfInkVotingViewModel.EvidenceType) {
        // Clean up previous state
        cleanupPlayer()
        tattooContentImageView.image = nil

        switch evidence {
        case let .photo(provider):
            tattooContentImageView.setHidden(false)
            provider?.providePreview(for: tattooContentImageView, size: mainContentContainer.bounds.size)
            provider?.providePreview(
                for: mediaPreviewImageView,
                size: mediaPreviewImageView.bounds.size
            )

        case let .video(playerItem, preview):
            tattooContentImageView.setHidden(true)
            preview?.providePreview(
                for: mediaPreviewImageView,
                size: mediaPreviewImageView.bounds.size
            )
            setupPlayerViewController(with: playerItem)
        }
    }

    func setupPlayerViewController(with playerItem: AVPlayerItem?) {
        guard let parentViewController else {
            assertionFailure("Parent expected")
            return
        }

        let player = AVPlayer(playerItem: playerItem)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        playerVC.showsPlaybackControls = true
        playerVC.videoGravity = .resizeAspectFill

        parentViewController.addChild(playerVC)
        mainContentContainer.addSubview(playerVC.view)
        playerVC.view.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        playerVC.didMove(toParent: parentViewController)

        playerViewController = playerVC
        player.play()
    }

    func cleanupPlayer() {
        playerViewController?.player?.pause()
        playerViewController?.willMove(toParent: nil)
        playerViewController?.view.removeFromSuperview()
        playerViewController?.removeFromParent()
        playerViewController = nil
    }
}

// MARK: - Preview Selection

private extension ProofOfInkVotingLayout {
    func selectMediaPreview() {
        isEvidenceSelected = true
        mediaPreviewContainer.layer.borderWidth = 2
        tattooPreviewContainer.layer.borderWidth = 0

        switch viewModel?.evidence {
        case .photo:
            tattooContentImageView.setHidden(false)
            playerViewController?.view.setHidden(true)
            if let provider = photoProvider {
                provider.providePreview(for: tattooContentImageView, size: mainContentContainer.bounds.size)
            }
        case .video:
            tattooContentImageView.setHidden(true)
            playerViewController?.view.setHidden(false)
            playerViewController?.player?.play()
        case .none:
            break
        }
    }

    func selectTattooPreview() {
        isEvidenceSelected = false
        mediaPreviewContainer.layer.borderWidth = 0
        tattooPreviewContainer.layer.borderWidth = 2

        // Pause video if playing
        playerViewController?.player?.pause()
        playerViewController?.view.setHidden(true)

        tattooContentImageView.setHidden(false)
        viewModel?.tattooProvider?.providePreview(
            for: tattooContentImageView,
            size: mainContentContainer.bounds.size
        )
    }

    @objc func mediaPreviewTapped() {
        guard !isEvidenceSelected else { return }
        selectMediaPreview()
    }

    @objc func tattooPreviewTapped() {
        guard isEvidenceSelected else { return }
        selectTattooPreview()
    }
}

// MARK: - Layout

private extension ProofOfInkVotingLayout {
    func setupLayout() {
        // Header
        headerTitleStack.addArrangedSubview(titleLabel)
        headerTitleStack.addArrangedSubview(subtitleLabel)

        mainContentContainer.addSubview(tattooContentImageView)

        addSubview(closeButton)
        addSubview(headerTitleStack)
        addSubview(reportButton)
        addSubview(mainContentContainer)
        addSubview(previewStack)
        addSubview(buttonsContainer)

        mediaPreviewContainer.addSubview(mediaPreviewImageView)
        tattooPreviewContainer.addSubview(tattooPreviewImageView)

        previewStack.addArrangedSubview(mediaPreviewContainer)
        previewStack.addArrangedSubview(tattooPreviewContainer)

        closeButton.snp.makeConstraints {
            $0.leading.equalToSuperview().inset(UIConstants.horizontalInsetMedium)
            $0.top.equalTo(safeAreaLayoutGuide.snp.top).offset(UIConstants.verticalInsetShort)
            $0.width.height.equalTo(32)
        }

        headerTitleStack.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.centerY.equalTo(closeButton)
            $0.leading.greaterThanOrEqualTo(closeButton.snp.trailing).offset(UIConstants.horizontalInsetShort)
            $0.trailing.lessThanOrEqualTo(reportButton.snp.leading).offset(-UIConstants.horizontalInsetShort)
        }

        reportButton.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(UIConstants.horizontalInsetMedium)
            $0.centerY.equalTo(closeButton)
            $0.width.height.equalTo(32)
        }

        mainContentContainer.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.width.equalToSuperview()
            $0.height.equalTo(mainContentContainer.snp.width)
        }

        tattooContentImageView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        mediaPreviewImageView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        tattooPreviewImageView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        mediaPreviewContainer.snp.makeConstraints {
            $0.width.height.equalTo(32)
        }

        tattooPreviewContainer.snp.makeConstraints {
            $0.width.height.equalTo(32)
        }

        previewStack.snp.makeConstraints {
            $0.bottom.equalTo(buttonsContainer.snp.top).offset(-UIConstants.verticalInsetWide)
            $0.centerX.equalToSuperview()
        }

        let buttonsHStack = UIStackView()
        buttonsHStack.axis = .horizontal
        buttonsHStack.spacing = 4
        buttonsHStack.distribution = .fillEqually

        buttonsHStack.addArrangedSubview(voteFalseButton)
        buttonsHStack.addArrangedSubview(voteTrueButton)

        buttonsContainer.addSubview(buttonsHStack)
        buttonsHStack.snp.makeConstraints {
            $0.directionalEdges.equalToSuperview().inset(8)
        }

        voteTrueButton.snp.makeConstraints {
            $0.height.equalTo(UIConstants.actionHeight)
        }

        voteFalseButton.snp.makeConstraints {
            $0.height.equalTo(UIConstants.actionHeight)
        }

        buttonsContainer.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(UIConstants.horizontalInsetMedium)
            $0.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(UIConstants.verticalInsetMedium)
        }
    }

    func performSizeBasedUpdates() {
        buttonsContainer.layer.cornerRadius = buttonsContainer.bounds.height / 2
    }

    func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        reportButton.addTarget(self, action: #selector(reportTapped), for: .touchUpInside)

        let mediaTap = UITapGestureRecognizer(target: self, action: #selector(mediaPreviewTapped))
        mediaPreviewContainer.addGestureRecognizer(mediaTap)

        let tattooTap = UITapGestureRecognizer(target: self, action: #selector(tattooPreviewTapped))
        tattooPreviewContainer.addGestureRecognizer(tattooTap)

        voteTrueButton.addTarget(self, action: #selector(voteTrueTapped), for: .touchUpInside)
        voteFalseButton.addTarget(self, action: #selector(voteFalseTapped), for: .touchUpInside)
    }

    @objc func closeTapped() {
        delegate?.proofOfInkVotingLayoutDidTapClose(self)
    }

    @objc func reportTapped() {
        delegate?.proofOfInkVotingLayoutDidTapReport(self)
    }

    @objc func voteTrueTapped() {
        delegate?.proofOfInkVotingLayoutDidVote(self, result: .positive)
    }

    @objc func voteFalseTapped() {
        delegate?.proofOfInkVotingLayoutDidVote(self, result: .negative)
    }
}
