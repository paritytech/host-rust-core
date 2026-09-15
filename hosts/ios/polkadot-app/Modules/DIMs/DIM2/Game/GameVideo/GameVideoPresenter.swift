import Foundation
import WebRTC
import SubstrateSdk

@MainActor
final class GameVideoPresenter {
    weak var view: GameVideoViewProtocol?

    private let wireframe: GameVideoWireframeProtocol
    private let interactor: GameVideoInteractorInputProtocol
    private let rtcClient: RTCClient
    private let cameraPermissionService: CameraPermissionServicing
    private let viewModelFactory: GameVideoViewModelMaking
    private let osMediator: OperatingSystemMediating
    private let logger: LoggerProtocol

    private var gameId: Game.Identifier?
    private var state: GameStateMachine.State?
    private var rtcIceConnectedFlags = [AccountId: Bool]()
    private var voting: GameVideoVoting?
    private var gestureAcceptances = Set<AccountId>()
    private var bannedPlayers = Set<AccountId>()
    private var playerTooltipShown: Bool = true
    private var swipeTooltipShown: Bool = true
    private var hasShownCameraPermissionAlert = false

    init(
        interactor: GameVideoInteractorInputProtocol,
        wireframe: GameVideoWireframeProtocol,
        rtcClient: RTCClient,
        cameraPermissionService: CameraPermissionServicing,
        viewModelFactory: GameVideoViewModelMaking,
        osMediator: OperatingSystemMediating = OperatingSystemMediator(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.rtcClient = rtcClient
        self.cameraPermissionService = cameraPermissionService
        self.viewModelFactory = viewModelFactory
        self.osMediator = osMediator
        self.logger = logger
    }
}

extension GameVideoPresenter: GameVideoPresenterProtocol {
    func setup() {
        interactor.setup()
        provideViewModel(isPlayersChanged: false)
    }

    func goToReport() {
        interactor.throttle(isGameFinished: true)
        logger.debug("Proceeding to report")

        if let gameId {
            logger.debug("Game id: \(gameId)")
            wireframe.showReport(from: view, for: gameId)
        } else {
            logger.debug("Missing game id, closing the view")
            close()
        }
    }

    func close() {
        interactor.throttle(isGameFinished: state?.isFinished == true)
        logger.debug("Closing")
        wireframe.close(view: view)
    }

    func onAppear() {
        osMediator.disableScreenSleep()

        Task { [weak self] in
            await self?.presentCameraPermissionIfNeeded()
        }
    }

    func onDisappear() {
        osMediator.enableScreenSleep()
    }

    func showTutorial() {
        wireframe.showTutorial(from: view)
    }

    func didDismissTooltip(_ tooltipType: GameVideoTooltipView.ViewModel) {
        switch tooltipType {
        case .showGesture,
             .copyHost:
            interactor.setTutorialTooltip(shown: true)
        case .swipeHint:
            interactor.setSwipeTooltip(shown: true)
        }
    }
}

extension GameVideoPresenter: GameVideoInteractorOutputProtocol {
    func didReceive(gameId: Game.Identifier?) {
        self.gameId = gameId
    }

    func didReceive(state: GameStateMachine.State?, isPlayersChanged: Bool) {
        self.state = state
        guard case .finished = state else {
            provideViewModel(isPlayersChanged: isPlayersChanged)
            return
        }
        goToReport()
    }

    func didReceive(rtcIceConnectedFlags: [AccountId: Bool]) {
        self.rtcIceConnectedFlags = rtcIceConnectedFlags
        provideViewModel(isPlayersChanged: false)
    }

    func didReceive(voting: GameVideoVoting?) {
        self.voting = voting
        provideViewModel(isPlayersChanged: false)
    }

    func didReceive(gestureAcceptances: Set<AccountId>) {
        self.gestureAcceptances = gestureAcceptances
        provideViewModel(isPlayersChanged: false)
    }

    func didReceive(bannedPlayers: Set<AccountId>) {
        self.bannedPlayers = bannedPlayers
        provideViewModel(isPlayersChanged: false)
    }

    func requestPreview(for player: AccountId) -> UIImage? {
        view?.requestPreview(for: player)
    }

    func didReceive(playerTooltipShown: Bool) {
        self.playerTooltipShown = playerTooltipShown
        provideViewModel(isPlayersChanged: false)
    }

    func didReceive(swipeTooltipShown: Bool) {
        self.swipeTooltipShown = swipeTooltipShown
        provideViewModel(isPlayersChanged: false)
    }

    func didReceiveIntendedGameEnded(intendedGameId: Game.Identifier) {
        gameId = intendedGameId
        goToReport()
    }
}

private extension GameVideoPresenter {
    @MainActor
    func presentCameraPermissionIfNeeded() async {
        var permission = cameraPermissionService.permission()

        if permission == .notDetermined {
            permission = await cameraPermissionService.requestPermission()
        }

        guard !hasShownCameraPermissionAlert, permission == .denied else {
            return
        }

        wireframe.askOpenApplicationSettings(
            with: String(localized: .Game.gameCameraPermissionVideoMessage),
            title: String(localized: .Game.gameCameraPermissionTitle),
            from: view
        ) { [weak self] result in
            guard result != .notPresented else { return }
            self?.hasShownCameraPermissionAlert = true
        }
    }

    func provideViewModel(isPlayersChanged: Bool) {
        let viewModel = viewModelFactory.makeViewModel(
            input: .init(
                state: state,
                rtcIceConnectedFlags: rtcIceConnectedFlags,
                voting: voting,
                gestureAcceptances: gestureAcceptances,
                bannedPlayers: bannedPlayers,
                isPlayersChanged: isPlayersChanged,
                isPlayerTooltipShown: playerTooltipShown,
                isSwipeTooltipShown: swipeTooltipShown
            )
        )
        view?.didReceive(
            viewModel: viewModel,
            rendererManager: rtcClient,
            playerVoteHandler: { [weak self] player, vote in
                self?.performVotingAction(for: player, vote: vote)
            },
            playerBanAction: { [weak self] player, isBanned in
                isBanned
                    ? self?.interactor.banPlayer(player)
                    : self?.interactor.unbanPlayer(player)
            }
        )
    }

    func performVotingAction(for player: AccountId, vote: GameVideoVotingState?) {
        interactor.performVotingAction(for: player, vote: vote)
    }
}
