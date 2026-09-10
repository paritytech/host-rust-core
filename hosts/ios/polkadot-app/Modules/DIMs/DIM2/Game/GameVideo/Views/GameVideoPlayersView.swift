import UIKit
import UIKit_iOS
import SubstrateSdk
import PolkadotUI

final class GameVideoPlayersView: UIView {
    let localPlayerView = GameVideoPlayerItemView(frame: .zero)
    let remotePlayerViews = (0 ..< Constants.remoteViewsCount)
        .map { _ in GameVideoPlayerItemView(frame: .zero) }
    let gridView = GridView(frame: .zero)
    let gestureAcceptanceConfettiView = GestureAcceptanceConfettiView()

    let hostIntroductionTopView: GenericBackgroundView<UILabel> = create {
        $0.alpha = 0
        $0.applyBackgroundStyle(.clear, cornerRadius: 0)

        $0.wrappedView.numberOfLines = 2
        $0.wrappedView.applyHostIntroductionStyle()
    }

    let hostIntroductionBottomView: GenericBackgroundView<UILabel> = create {
        $0.alpha = 0
        $0.applyBackgroundStyle(.clear, cornerRadius: 0)

        $0.wrappedView.numberOfLines = 1
        $0.wrappedView.applyHostIntroductionStyle()
    }

    private(set) var remotePlayerViewsByAccountId = [AccountId: GameVideoPlayerItemView]()
    private(set) var placeholderRemotePlayerViews = [GameVideoPlayerItemView]()

    private(set) var playerViewsForGrid = [GameVideoPlayerItemView]()
    private(set) var isLocalPlayerViewIncludedInGrid = false

    weak var hostPlayerView: GameVideoPlayerItemView?

    var animationState = AnimationState.hidden

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension GameVideoPlayersView {
    func bind(
        viewModel: GameVideoViewLayout.ViewModel,
        rendererManager: RTCRendererManaging,
        playerVoteHandler: @escaping PlayerVoteAction,
        playerBanAction: @escaping PlayerBanAction
    ) {
        setupPlayerViews(
            with: viewModel,
            rendererManager: rendererManager,
            playerVoteHandler: playerVoteHandler,
            playerBanAction: playerBanAction
        )
        setupGestureAcceptanceConfetti(with: viewModel)
        setupHostIntroductionLabels(with: viewModel)
        setupAnimationState(with: viewModel)
    }

    func requestPreview(for player: AccountId) -> UIImage? {
        remotePlayerViewsByAccountId[player]?.requestPreview()
    }
}

private extension GameVideoPlayersView {
    enum Constants {
        static let gridViewsCount = 6
        static let remoteViewsCount = 5
    }

    var logger: Logger {
        .shared
    }

    func setupLayout() {
        addSubview(gridView)
        gridView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(8)
            $0.top.bottom.equalToSuperview()
        }

        let itemViews = [localPlayerView] + remotePlayerViews
        itemViews.forEach { itemView in
            addSubview(itemView)
            itemView.alpha = 0
        }

        localPlayerView.addGestureAcceptanceConfettiView(gestureAcceptanceConfettiView)
    }

    func setupGestureAcceptanceConfetti(
        with viewModel: GameVideoViewLayout.ViewModel
    ) {
        gestureAcceptanceConfettiView.bind(
            tier: viewModel.gestureAcceptanceTier
        )
    }

    func setupPlayerViews(
        with viewModel: GameVideoViewLayout.ViewModel,
        rendererManager: RTCRendererManaging,
        playerVoteHandler: @escaping PlayerVoteAction,
        playerBanAction: @escaping PlayerBanAction
    ) {
        prepareRemotePlayerViews(for: viewModel)

        preparePlayerViewsForGrid(
            with: viewModel,
            rendererManager: rendererManager,
            playerVoteHandler: playerVoteHandler,
            playerBanAction: playerBanAction
        )

        guard !isLocalPlayerViewIncludedInGrid else {
            return
        }
        localPlayerView.bind(
            viewModel: viewModel,
            player: .defaultLocal(accountId: viewModel.accountId),
            rendererManager: rendererManager,
            playerVoteHandler: playerVoteHandler,
            playerBanAction: playerBanAction
        )
    }

    func prepareRemotePlayerViews(
        for viewModel: GameVideoViewLayout.ViewModel
    ) {
        let isEmpty = remotePlayerViewsByAccountId.isEmpty
            && placeholderRemotePlayerViews.isEmpty

        let shouldReassign = isEmpty
            || viewModel.isPlayersChanged

        guard shouldReassign else {
            return
        }

        logger.debug("Reassigning remote player views")
        logger.debug("isEmpty = \(isEmpty); isPlayersChanged = \(viewModel.isPlayersChanged)")

        remotePlayerViewsByAccountId.removeAll(keepingCapacity: true)
        placeholderRemotePlayerViews.removeAll(keepingCapacity: true)

        var remoteIndex = 0

        for player in viewModel.orderedPlayers where !player.isLocal {
            guard remoteIndex < remotePlayerViews.count else {
                logger.error("Remote players count exceeded")
                logger.error("Players count: \(viewModel.orderedPlayers.count)")
                break
            }
            let remoteView = remotePlayerViews[remoteIndex]
            remoteView.prepareForReuse()
            remotePlayerViewsByAccountId[player.accountId] = remoteView
            remoteIndex += 1
        }

        for index in remoteIndex ..< remotePlayerViews.count {
            let placeholderView = remotePlayerViews[index]
            placeholderView.prepareForReuse()
            placeholderView.setupAsPlaceholder(true)
            placeholderRemotePlayerViews.append(placeholderView)
        }
    }

    func preparePlayerViewsForGrid(
        with viewModel: GameVideoViewLayout.ViewModel,
        rendererManager: RTCRendererManaging,
        playerVoteHandler: @escaping PlayerVoteAction,
        playerBanAction: @escaping PlayerBanAction
    ) {
        playerViewsForGrid.removeAll(keepingCapacity: true)
        isLocalPlayerViewIncludedInGrid = false

        // TODO: - Think how to implement views distribution more simpler/effective
        // The initial idea is to use the same remote views pool and
        // to bind 1 view to 1 user until the players list changes

        guard !viewModel.orderedPlayers.isEmpty else {
            // just fill with all views
            playerViewsForGrid = [localPlayerView] + remotePlayerViews
            return
        }

        let playersCount = viewModel.orderedPlayers.count

        var placeholderIndex = 0

        func appendPlaceholder() {
            guard placeholderIndex < placeholderRemotePlayerViews.count else {
                logger.error("Prepared placeholder count exceeded")
                addUnexpectedPlaceholderToGrid(withPlayersCount: playersCount)
                return
            }
            playerViewsForGrid.append(placeholderRemotePlayerViews[placeholderIndex])
            placeholderIndex += 1
        }

        for gridIndex in 0 ..< Constants.gridViewsCount {
            guard gridIndex < playersCount else {
                appendPlaceholder()
                continue
            }

            let player = viewModel.orderedPlayers[gridIndex]

            guard !player.isLocal else {
                localPlayerView.bind(
                    viewModel: viewModel,
                    player: player,
                    rendererManager: rendererManager,
                    playerVoteHandler: playerVoteHandler,
                    playerBanAction: playerBanAction
                )
                playerViewsForGrid.append(localPlayerView)
                isLocalPlayerViewIncludedInGrid = true
                continue
            }

            guard let remoteView = remotePlayerViewsByAccountId[player.accountId] else {
                logger.error("Missing cached remote player view")
                addUnexpectedPlaceholderToGrid(withPlayersCount: playersCount)
                continue
            }

            remoteView.bind(
                viewModel: viewModel,
                player: player,
                rendererManager: rendererManager,
                playerVoteHandler: playerVoteHandler,
                playerBanAction: playerBanAction
            )
            playerViewsForGrid.append(remoteView)
        }
    }

    func addUnexpectedPlaceholderToGrid(withPlayersCount count: Int) {
        logger.error("Players count: \(count)")
        let view = GameVideoPlayerItemView(frame: .zero)
        view.setupAsPlaceholder(true)
        playerViewsForGrid.append(view)
    }

    func setupHostIntroductionLabels(with viewModel: GameVideoViewLayout.ViewModel) {
        hostIntroductionTopView.wrappedView.applyHostIntroductionText(viewModel.isOwnHosting
            ? String(localized: .Game.gameVideoYouAreHost)
            : String(localized: .Game.gameVideoMeetNewHost))
        hostIntroductionBottomView.wrappedView.applyHostIntroductionText(viewModel.isOwnHosting
            ? String(localized: .Game.gameVideoShowGesture)
            : String(localized: .Game.gameVideoCopyGesture))
    }
}

private extension UILabel {
    func applyHostIntroductionStyle() {
        textColor = .textAndIconsPrimaryDark
        font = UIFont.headlineMulishXL()
        textAlignment = .center
    }

    func applyHostIntroductionText(_ text: String) {
        attributedText = LabelStyle.headlineMulishXL().attributedString(
            from: text,
            textColor: .textAndIconsPrimaryDark,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
    }
}
