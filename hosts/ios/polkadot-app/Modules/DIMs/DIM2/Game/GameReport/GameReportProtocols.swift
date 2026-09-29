import WebRTC
import UIKitExt

protocol GameReportViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: GameReportViewLayout.ViewModel)
    func didReceive(confirmButtonState: GameReportViewLayout.ConfirmButtonState)
}

@MainActor
protocol GameReportPresenterProtocol: AnyObject {
    func setup()
    func toggleVote(_ gameVote: GameVote)
    func confirmReport()
    func registerForNextGame()
}

protocol GameReportInteractorInputProtocol: AnyObject {
    func setup()
    func reportCurrentVotes()
    func toggleVote(_ gameVote: GameVote)
}

@MainActor
protocol GameReportInteractorOutputProtocol: AnyObject {
    func didReceive(votes: [GameVote])
    func didReceive(isReportInProgress: Bool)
    func didReceive(error: Error)
    func didReportCurrentVotes(context: ReportSuccessContext)
    func didReceiveVotingAvailable()
    func didReceiveVotingUnavailable(endedGameDate: Date?)
}

@MainActor
protocol GameReportWireframeProtocol: ErrorPresentable, AlertPresentable {
    func close(view: GameReportViewProtocol?)
    func registerForNextGame(view: GameReportViewProtocol?)
    func showReveal(view: GameReportViewProtocol?, context: ReportSuccessContext)
}
