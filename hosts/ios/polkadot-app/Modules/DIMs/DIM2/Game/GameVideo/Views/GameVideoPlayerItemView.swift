import UIKit
import UIKit_iOS
import WebRTC
import PolkadotUI
import DesignSystem

final class GameVideoPlayerItemView: UIView {
    var renderer: FilteredMTKRenderer? = prepareRenderer()

    let rendererViewContainer: UIView = create {
        $0.clipsToBounds = true
        $0.layer.cornerRadius = Constants.contentCornerRadius
        $0.backgroundColor = .backgroundTertiary
    }

    let contentView: UIView = create {
        $0.clipsToBounds = true
        $0.layer.cornerRadius = Constants.contentCornerRadius
    }

    private let confettiHaloView = GameVideoPlayerConfettiHaloView()

    private let noiseView: GameVideoNoiseView = create {
        $0.layer.cornerRadius = Constants.contentCornerRadius
        $0.isHidden = true
    }

    private let frameView = TileFrameView(
        model: TileFrameModel(
            palette: .dim2GameVideoPlayer,
            strength: .soft
        )
    )

    private let attestationOverlayView: AttestationOverlayView = create {
        $0.cornerRadius = Constants.contentCornerRadius
    }

    private let banToggleButton: RoundedButton = create {
        $0.applyBarButtonItemStyle()
    }

    private let bannedOverlayView: GameVideoPlayerBannedOverlayView = create {
        $0.isHidden = true
    }

    private var currentRendererPlayer: GameVideoViewLayout.Player?
    private var currentPlayer: GameVideoViewLayout.Player?
    private var currentViewModel: GameVideoViewLayout.ViewModel?
    private var frameStrength = TileFrameModel.Strength.soft
    private var isFrameVisible = true

    private weak var rendererManager: RTCRendererManaging?

    private var rendererSuspended: Bool = false

    // Set immediately on tap, cleared when fresh model arrives
    // Improves UX, no delay between tap and ban ui update
    private var localBannedOverride: Bool?

    private var votingHandler: PlayerVoteAction?
    private var banActionHandler: PlayerBanAction?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()

        attestationOverlayView.controller.delegate = self
        banToggleButton.addTarget(self, action: #selector(didTapBanToggle), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        disconnectRenderer()
    }
}

extension GameVideoPlayerItemView {
    func applyHostIntroductionStyle() {
        frameStrength = .strong
        updateFrameViewStyle()
    }

    func applyRegularStyle() {
        frameStrength = .soft
        updateFrameViewStyle()
    }

    func prepareForReuse() {
        disconnectRenderer()
        renderer = Self.prepareRenderer()

        attestationOverlayView.prepareForReuse()
        attestationOverlayView.controller.delegate = self
        confettiHaloView.reset()

        frameStrength = .soft
        setupAsPlaceholder(false)
        hideNoise()

        banToggleButton.isHidden = true
        bannedOverlayView.isHidden = true
        banActionHandler = nil
        localBannedOverride = nil
        currentPlayer = nil
        currentViewModel = nil
    }

    func setupAsPlaceholder(_ isPlaceholder: Bool) {
        setFrameVisible(!isPlaceholder)
        contentView.isHidden = isPlaceholder
    }

    func bind(
        viewModel: GameVideoViewLayout.ViewModel,
        player: GameVideoViewLayout.Player,
        rendererManager: RTCRendererManaging,
        playerVoteHandler: @escaping PlayerVoteAction,
        playerBanAction: @escaping PlayerBanAction
    ) {
        localBannedOverride = nil
        currentPlayer = player
        currentViewModel = viewModel
        updateFrameViewStyle()
        setFrameVisible(viewModel.state != .waiting)

        bindRendering(
            for: player,
            rendererManager: rendererManager
        )

        attestationOverlayView.bind(
            viewModel: player.attestationOverlayModel,
            delegate: self
        )

        bindBanState(player: player)

        votingHandler = playerVoteHandler
        banActionHandler = playerBanAction
    }

    func requestPreview() -> UIImage? {
        guard let renderer,
              !renderer.view.isHidden,
              currentRendererPlayer != nil else {
            return nil
        }

        let size = renderer.view.bounds.size

        guard size != .zero else {
            return nil
        }

        return renderer.makeUnfilteredPreviewImage()
    }

    func addGestureAcceptanceConfettiView(_ confettiView: GestureAcceptanceConfettiView) {
        confettiView.clipsToBounds = true
        confettiView.layer.cornerRadius = Constants.contentCornerRadius
        confettiView.onFinale = { [weak self] in
            self?.confettiHaloView.play()
        }
        contentView.insertSubview(
            confettiView,
            aboveSubview: rendererViewContainer
        )
        confettiView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
    }
}

private final class GameVideoPlayerConfettiHaloView: UIView {
    private let halo = HaloOverlay()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isHidden = true
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(halo)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        halo.frame = bounds
    }

    func play() {
        isHidden = false
        halo.play()
    }

    func reset() {
        halo.reset()
        isHidden = true
    }
}

private extension GameVideoPlayerItemView {
    var logger: Logger { .shared }

    enum Constants {
        static let bezelWidth = CGFloat(7)
        static let contentCornerRadius = CGFloat(9)
        static let buttonSize = CGFloat(32)
        static let buttonInset = CGFloat(12)
        static let confettiHaloBleed = CGFloat(58)
    }

    static func prepareRenderer() -> FilteredMTKRenderer? {
        let renderer = try? FilteredMTKRenderer()
        renderer?.view.contentMode = .scaleAspectFill
        return renderer
    }

    func setupLayout() {
        addSubview(frameView)
        frameView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(confettiHaloView)
        confettiHaloView.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(-Constants.confettiHaloBleed)
        }

        addSubview(contentView)
        contentView.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(Constants.bezelWidth)
        }

        contentView.addSubview(rendererViewContainer)
        rendererViewContainer.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        contentView.addSubview(attestationOverlayView)
        attestationOverlayView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        contentView.addSubview(noiseView)
        noiseView.snp.makeConstraints {
            $0.edges.equalTo(rendererViewContainer)
        }

        contentView.addSubview(bannedOverlayView)
        bannedOverlayView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        contentView.addSubview(banToggleButton)
        banToggleButton.snp.makeConstraints {
            $0.width.height.equalTo(Constants.buttonSize)
            $0.top.trailing.equalToSuperview().inset(Constants.buttonInset)
        }
        banToggleButton.isHidden = true
    }

    func setFrameVisible(_ isVisible: Bool) {
        guard isFrameVisible != isVisible else {
            return
        }

        isFrameVisible = isVisible
        frameView.isHidden = !isVisible
        contentView.layer.cornerRadius = isVisible ? Constants.contentCornerRadius : 0
        rendererViewContainer.layer.cornerRadius = isVisible ? Constants.contentCornerRadius : 0

        contentView.snp.remakeConstraints {
            $0.edges.equalToSuperview().inset(isVisible ? Constants.bezelWidth : 0)
        }
    }

    func bindBanState(player: GameVideoViewLayout.Player) {
        let isBanned = localBannedOverride ?? player.isBanned

        bannedOverlayView.isHidden = !isBanned
        rendererViewContainer.isHidden = isBanned
        if isBanned {
            banToggleButton.isHidden = false
            banToggleButton.setIcon(
                .eye.withTintColor(.textAndIconsPrimaryDark)
            )
        } else if player.canBeBanned {
            banToggleButton.isHidden = false
            banToggleButton.setIcon(
                .crossedEye.withTintColor(.textAndIconsPrimaryDark)
            )
        } else {
            banToggleButton.isHidden = true
        }
    }

    func updateFrameViewStyle() {
        guard let currentPlayer else {
            return
        }

        frameView.bind(model: frameModel(for: currentPlayer))
    }

    func frameModel(for player: GameVideoViewLayout.Player) -> TileFrameModel {
        TileFrameModel(
            palette: framePalette(for: player),
            strength: frameStrength
        )
    }

    func framePalette(for player: GameVideoViewLayout.Player) -> TileFrameModel.Palette {
        if isLocalHostIntroduction(player: player) {
            return .dim2GameVideoMe
        }

        if player.isHost {
            return .dim2GameVideoHost
        }

        if player.isLocal {
            return .dim2GameVideoMe
        }

        return .dim2GameVideoPlayer
    }

    func isLocalHostIntroduction(player: GameVideoViewLayout.Player) -> Bool {
        player.isLocal &&
            player.isHost &&
            currentViewModel?.state == .hostIntroduction
    }

    private func showNoise() {
        noiseView.isHidden = false
        noiseView.startAnimating()
    }

    private func hideNoise() {
        noiseView.stopAnimating()
        noiseView.isHidden = true
    }

    func bindRendering(
        for player: GameVideoViewLayout.Player,
        rendererManager: RTCRendererManaging
    ) {
        switch player.rendererState {
        case .connected:
            connectRenderer(for: player, rendererManager: rendererManager)
            renderer?.view.isHidden = false
            hideNoise()
        case .suspended:
            detachRenderer()
            renderer?.view.isHidden = false
            hideNoise()
        case .disconnected:
            disconnectRenderer()
            renderer?.view.isHidden = true
            showNoise()
        }

        renderer?.updateProviders(
            overlays: player.filtersConfiguration.overlayProviders,
            looks: player.filtersConfiguration.lookProviders,
            spatial: player.filtersConfiguration.spatialEffectProvider
        )
    }

    func connectRenderer(
        for player: GameVideoViewLayout.Player,
        rendererManager: RTCRendererManaging
    ) {
        if updateExistingRenderer(for: player, rendererManager: rendererManager) {
            return
        }

        guard canConnectRenderer(player: player, rendererManager: rendererManager) else {
            return
        }

        let peerId = player.accountId.toHex()
        logger.debug("Connecting renderer for \(player.isLocal ? "local" : "remote") player \(peerId)")

        disconnectRenderer()
        currentRendererPlayer = player
        setupRendererView(for: player)
        attachRenderer(for: player, rendererManager: rendererManager)
    }

    func canConnectRenderer(
        player: GameVideoViewLayout.Player,
        rendererManager: RTCRendererManaging
    ) -> Bool {
        if player.isLocal {
            return true
        }

        let hasTrack = rendererManager.hasRemoteVideoTrack(for: player.accountId)

        if !hasTrack {
            let peerId = player.accountId.toHex()
            logger.warning("No remote video track yet for remote peer \(peerId)")
        }

        return hasTrack
    }

    /// Returns `true` if the renderer is already bound to this player and no reconnection is needed.
    func updateExistingRenderer(
        for player: GameVideoViewLayout.Player,
        rendererManager: RTCRendererManaging
    ) -> Bool {
        guard currentRendererPlayer?.accountId == player.accountId else {
            return false
        }

        currentRendererPlayer = player

        if rendererSuspended {
            attachRenderer(for: player, rendererManager: rendererManager)
        }

        return true
    }

    func disconnectRenderer() {
        detachRenderer()

        rendererManager = nil
        rendererViewContainer.subviews.forEach { $0.removeFromSuperview() }

        currentRendererPlayer = nil
        rendererSuspended = false
    }

    func attachRenderer(
        for player: GameVideoViewLayout.Player,
        rendererManager: RTCRendererManaging
    ) {
        guard let renderer else { return }

        self.rendererManager = rendererManager

        if player.isLocal {
            rendererManager.connectLocalRenderer(renderer)
        } else {
            rendererManager.connectRenderer(renderer, for: player.accountId)
        }

        rendererSuspended = false
    }

    func detachRenderer() {
        guard let currentRendererPlayer, let renderer else {
            return
        }

        if currentRendererPlayer.isLocal {
            rendererManager?.disconnectLocalRenderer(renderer)
        } else {
            rendererManager?.disconnectRenderer(renderer, for: currentRendererPlayer.accountId)
        }

        rendererSuspended = true
    }

    func setupRendererView(for player: GameVideoViewLayout.Player) {
        guard let renderer else { return }

        let rendererView = renderer.view
        rendererView.transform = player.isLocal
            ? CGAffineTransform(scaleX: -1.0, y: 1.0)
            : .identity

        rendererViewContainer.subviews.forEach { $0.removeFromSuperview() }
        rendererViewContainer.addSubview(rendererView)
        rendererView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
    }

    @objc func didTapBanToggle() {
        guard let currentPlayer else {
            return
        }
        let newState = !(localBannedOverride ?? currentPlayer.isBanned)
        localBannedOverride = newState
        bindBanState(player: currentPlayer)
        banActionHandler?(currentPlayer.accountId, newState)
    }
}

extension GameVideoPlayerItemView: AttestationOverlayControllerDelegate {
    func attestationControllerDidBeginAttestation(
        controller _: AttestationOverlayController
    ) {
        guard let currentRendererPlayer, let votingHandler else {
            return
        }
        votingHandler(currentRendererPlayer.accountId, nil)
    }

    func attestationController(
        controller _: AttestationOverlayController,
        didChangeAttestation attested: Bool?
    ) {
        guard let currentRendererPlayer, let votingHandler else {
            return
        }
        let state: GameVideoVotingState =
            switch attested {
            case .some(true): .positive
            case .some(false): .negative
            case .none: .notDecided
            }
        votingHandler(currentRendererPlayer.accountId, state)
    }
}

private extension TileFrameModel.Palette {
    static let dim2GameVideoHost = TileFrameModel.Palette(
        bezelColors: [
            .dim2GameVideoHostFrameGradientStart,
            .dim2GameVideoHostFrameGradientMiddle,
            .dim2GameVideoHostFrameGradientEnd
        ],
        glowColor: .dim2GameVideoHostFrameGlow
    )

    static let dim2GameVideoMe = TileFrameModel.Palette(
        bezelColors: [
            .dim2GameVideoMeFrameGradientStart,
            .dim2GameVideoMeFrameGradientMiddle,
            .dim2GameVideoMeFrameGradientEnd
        ],
        glowColor: .dim2GameVideoMeFrameGlow
    )

    static let dim2GameVideoPlayer = TileFrameModel.Palette(
        bezelColors: [
            .dim2GameVideoPlayerFrameGradientStart,
            .dim2GameVideoPlayerFrameGradientMiddle,
            .dim2GameVideoPlayerFrameGradientEnd
        ],
        glowColor: .dim2GameVideoPlayerFrameGlow
    )
}
