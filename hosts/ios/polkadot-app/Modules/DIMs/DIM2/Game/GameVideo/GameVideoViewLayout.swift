import UIKit
import UIKit_iOS
import SubstrateSdk
import PolkadotUI

final class GameVideoViewLayout: UIView {
    var onTooltipDismissed: ((GameVideoTooltipView.ViewModel) -> Void)?

    // "navigation bar"
    let headerView = GameVideoHeaderView(frame: .zero)

    // background
    let stripeBackgroundView = DiagonalStripeBackgroundView(frame: .zero)

    let waitingCountdownView = GameVideoWaitingCountdownView(frame: .zero)

    // swipe hint tooltip view
    lazy var swipeTooltipView = GameVideoTooltipView(frame: .zero)

    // grid view
    let playersView = GameVideoPlayersView(frame: .zero)

    // first-time player's tooltips
    lazy var playerTooltipView = GameVideoTooltipView(frame: .zero)

    // game progress view
    let roundView = GameVideoRoundView(frame: .zero)

    // bottom view
    let footerView = GameVideoFooterView(frame: .zero)

    let disconnectedOverlayView = GameVideoHostDisconnectedView()

    // utilities
    let tooltipAppearanceAnimator: ViewAnimatorProtocol = FadeAnimator(
        from: 0,
        to: 1,
        duration: 0.3
    )
    let tooltipDisappearanceAnimator: ViewAnimatorProtocol = FadeAnimator(
        from: 1,
        to: 0,
        duration: 0.3
    )

    var tooltipTimer: Timer?
    var currentTooltipModel: GameVideoTooltipView.ViewModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension GameVideoViewLayout {
    struct ViewModel {
        struct WaitingCountdown {
            let text: String
            let secondsRemaining: Int
        }

        let state: State
        let accountId: AccountId
        let waitingCountdown: WaitingCountdown?
        let orderedPlayers: [Player]
        let gestureAcceptanceTier: GestureAcceptanceTier
        let isPlayersChanged: Bool
        let subroundsCount: Int
        let currentSubroundCount: Int
        let timerInfo: TimerInfo
        let isOwnHosting: Bool
        let tooltipViewModel: GameVideoTooltipView.ViewModel?
    }

    enum State {
        case waiting
        case subroundStart
        case hostIntroduction
        case hosting
        case hostingEnd
    }

    enum RendererState {
        case connected
        case suspended
        case disconnected
    }

    enum GestureAcceptanceTier {
        case none
        case level(Int)
    }

    struct Player {
        let accountId: AccountId
        let votingState: GameVideoVotingState
        let isHost: Bool
        let isLocal: Bool
        let isBanned: Bool
        let rendererState: RendererState
        let filtersConfiguration: FilteredRendererConfiguration
        let attestationOverlayModel: AttestationOverlayView.ViewModel

        static func defaultLocal(
            accountId: AccountId,
            rendererState: GameVideoViewLayout.RendererState = .connected
        ) -> Self {
            .init(
                accountId: accountId,
                votingState: .notDecided,
                isHost: false,
                isLocal: true,
                isBanned: false,
                rendererState: rendererState,
                filtersConfiguration: FilteredRendererConfiguration.original,
                attestationOverlayModel: .empty
            )
        }
    }

    struct TimerInfo {
        let counter: Int
        let progress: CGFloat

        static func empty() -> Self {
            .init(counter: 0, progress: 1)
        }
    }

    func bind(
        viewModel: ViewModel,
        rendererManager: RTCRendererManaging,
        playerVoteHandler: @escaping PlayerVoteAction,
        playerBanAction: @escaping PlayerBanAction
    ) {
        stripeBackgroundView.setIntroAnimationActive(
            viewModel.state == .hostIntroduction,
            replayKey: viewModel.currentSubroundCount
        )
        stripeBackgroundView.setShimmerActive(viewModel.state == .waiting)

        switch viewModel.state {
        case .waiting:
            hideDisconnectedOverlay()
            hideGameViews()
            showWaitingCountdownView(viewModel: viewModel)
        case .hostIntroduction:
            hideWaitingCountdownView()
            hideDisconnectedOverlay()
            setupPlayersViewConstraints(hasOffsets: false)
            showPlayersView()
        case .hostingEnd:
            hideWaitingCountdownView()
            hideDisconnectedOverlay()
            setupPlayersViewConstraints(hasOffsets: true)
            showPlayersView()
        case .hosting
            where viewModel.orderedPlayers.contains(where: \.isDisconnectedHost):
            hideWaitingCountdownView()
            setupPlayersViewConstraints(hasOffsets: true)
            showPlayersView()
            showDisconnectedOverlay()
        case .hosting:
            hideWaitingCountdownView()
            hideDisconnectedOverlay()
            setupPlayersViewConstraints(hasOffsets: true)
            showPlayersView()
        case .subroundStart:
            hideWaitingCountdownView()
            hideDisconnectedOverlay()
            showRoundView()
        }

        if viewModel.state != .waiting {
            playersView.bind(
                viewModel: viewModel,
                rendererManager: rendererManager,
                playerVoteHandler: playerVoteHandler,
                playerBanAction: playerBanAction
            )
        }

        headerView.bind(viewModel: viewModel)
        roundView.bind(viewModel: viewModel)
        footerView.bind(viewModel: viewModel)
        setupTooltip(viewModel: viewModel)
    }

    func requestPreview(for player: AccountId) -> UIImage? {
        playersView.requestPreview(for: player)
    }
}

extension GameVideoViewLayout {
    var closeButton: RoundedButton {
        headerView.closeButton
    }

    var tutorialButton: RoundedButton {
        footerView.tutorialButton
    }
}

private extension GameVideoViewLayout {
    func setupLayout() {
        backgroundColor = .bgSurfaceMain

        addSubview(stripeBackgroundView)
        stripeBackgroundView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(playersView)
        playersView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(headerView)
        headerView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(safeAreaLayoutGuide.snp.top)
        }

        addSubview(footerView)
        footerView.snp.makeConstraints {
            $0.leading.trailing.bottom.equalToSuperview()
            $0.top.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-104)
        }

        addSubview(waitingCountdownView)
        waitingCountdownView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(headerView.snp.bottom)
            $0.bottom.equalTo(footerView.snp.top)
        }

        addSubview(roundView)
        roundView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(headerView.snp.bottom)
            $0.bottom.equalTo(footerView.snp.top)
        }
    }

    func setupPlayersViewConstraints(hasOffsets: Bool) {
        if hasOffsets {
            playersView.snp.remakeConstraints {
                $0.leading.trailing.equalToSuperview()
                $0.top.equalTo(headerView.snp.bottom).offset(32)
                $0.bottom.equalTo(footerView.snp.top)
            }
        } else {
            playersView.snp.remakeConstraints {
                $0.edges.equalToSuperview()
            }
        }
    }

    func showPlayersView() {
        playersView.isHidden = false
        roundView.isHidden = true
    }

    func showRoundView() {
        playersView.isHidden = true
        roundView.isHidden = false
    }

    func hideGameViews() {
        playersView.isHidden = true
        roundView.isHidden = true
    }

    func showWaitingCountdownView(viewModel: GameVideoViewLayout.ViewModel) {
        guard let waitingCountdown = viewModel.waitingCountdown else {
            waitingCountdownView.isHidden = true
            return
        }

        waitingCountdownView.isHidden = false
        waitingCountdownView.bind(viewModel: waitingCountdown)
    }

    func hideWaitingCountdownView() {
        waitingCountdownView.isHidden = true
    }

    func showDisconnectedOverlay() {
        guard disconnectedOverlayView.superview == nil else {
            return
        }
        addSubview(disconnectedOverlayView)
        disconnectedOverlayView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(footerView.snp.top)
        }
    }

    func hideDisconnectedOverlay() {
        disconnectedOverlayView.removeFromSuperview()
    }
}

private extension GameVideoViewLayout.Player {
    var isDisconnectedHost: Bool {
        isHost && rendererState == .disconnected
    }
}

extension GameVideoViewLayout.Player {
    var canBeBanned: Bool {
        !isLocal
    }
}
