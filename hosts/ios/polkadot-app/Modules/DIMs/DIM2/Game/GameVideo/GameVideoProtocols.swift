import WebRTC
import SubstrateSdk
import UIKitExt

typealias PlayerVoteAction = (
    _ player: AccountId,
    _ vote: GameVideoVotingState? // If nil user not decided yet (gesture in flight)
) -> Void

typealias PlayerBanAction = (
    _ player: AccountId,
    _ isBanned: Bool
) -> Void

enum PlayerVoteActionState {
    case interactedWith
}

protocol GameVideoViewProtocol: ControllerBackedProtocol {
    func didReceive(
        viewModel: GameVideoViewLayout.ViewModel,
        rendererManager: RTCRendererManaging,
        playerVoteHandler: @escaping PlayerVoteAction,
        playerBanAction: @escaping PlayerBanAction
    )

    func requestPreview(for player: AccountId) -> UIImage?
}

@MainActor
protocol GameVideoPresenterProtocol: AnyObject {
    func setup()
    func onAppear()
    func onDisappear()
    func goToReport()
    func showTutorial()
    func close()
    func didDismissTooltip(_ tooltipType: GameVideoTooltipView.ViewModel)
}

protocol GameVideoInteractorInputProtocol: AnyObject {
    func setup()
    func throttle(isGameFinished: Bool)
    func performVotingAction(for player: AccountId, vote: GameVideoVotingState?)
    func banPlayer(_ player: AccountId)
    func unbanPlayer(_ player: AccountId)
    func setTutorialTooltip(shown: Bool)
    func setSwipeTooltip(shown: Bool)
}

@MainActor
protocol GameVideoInteractorOutputProtocol: AnyObject {
    func didReceive(gameId: Game.Identifier?)
    func didReceive(state: GameStateMachine.State?, isPlayersChanged: Bool)
    func didReceive(rtcIceConnectedFlags: [AccountId: Bool])
    func didReceive(voting: GameVideoVoting?)
    func didReceive(gestureAcceptances: Set<AccountId>)
    func didReceive(bannedPlayers: Set<AccountId>)
    func didReceive(playerTooltipShown: Bool)
    func didReceive(swipeTooltipShown: Bool)
    func requestPreview(for player: AccountId) -> UIImage?
    func didReceiveIntendedGameEnded(intendedGameId: Game.Identifier)
}

@MainActor
protocol GameVideoWireframeProtocol: ApplicationSettingsPresentable {
    func showReport(from view: GameVideoViewProtocol?, for gameId: Game.Identifier)
    func showTutorial(from view: GameVideoViewProtocol?)
    func close(view: GameVideoViewProtocol?)
}
