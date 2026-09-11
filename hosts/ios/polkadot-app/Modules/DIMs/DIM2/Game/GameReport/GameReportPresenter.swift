import Foundation
import Foundation_iOS
import WebRTC

final class GameReportPresenter {
    weak var view: GameReportViewProtocol?

    private let interactor: GameReportInteractorInputProtocol
    private let wireframe: GameReportWireframeProtocol
    private let viewModelProvider: GameReportViewModelProviding

    private var votes = [GameVote]()
    private var isVotingAvailable = false
    private var isGameInfoReceived = false
    private var isReported = false
    private var endedGameDate: Date?
    private var confirmButtonState: GameReportViewLayout.ConfirmButtonState = .confirm
    private let autoConfirmTimer: CountdownTimerProtocol = CountdownTimer()

    init(
        interactor: GameReportInteractorInputProtocol,
        wireframe: GameReportWireframeProtocol,
        viewModelProvider: GameReportViewModelProviding
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelProvider = viewModelProvider
        autoConfirmTimer.delegate = self
    }

    deinit {
        autoConfirmTimer.delegate = nil
        autoConfirmTimer.stop()
    }
}

extension GameReportPresenter: GameReportPresenterProtocol {
    func setup() {
        view?.didReceive(viewModel: .loading)
        interactor.setup()
    }

    func toggleVote(_ gameVote: GameVote) {
        cancelAutoConfirmForVoteChange()
        interactor.toggleVote(gameVote)
    }

    func confirmReport() {
        stopAutoConfirmTimer()
        interactor.reportCurrentVotes()
    }

    func registerForNextGame() {
        Task { @MainActor in
            wireframe.registerForNextGame(view: view)
        }
    }

    func close() {
        Task { @MainActor in
            wireframe.close(view: view)
        }
    }
}

extension GameReportPresenter: GameReportInteractorOutputProtocol {
    func didReceive(votes: [GameVote]) {
        self.votes = votes
        guard isGameInfoReceived else { return }
        provideViewModel()
    }

    func didReceive(isReportInProgress: Bool) {
        confirmButtonState = isReportInProgress ? .loading : .confirm
        provideViewModel()
    }

    func didReceive(error: Error) {
        if let view {
            _ = wireframe.present(error: error, from: view)
        }
    }

    func didReportCurrentVotes(context: ReportSuccessContext) {
        isReported = true
        provideViewModel()
        wireframe.showReveal(view: view, context: context)
    }

    func didReceiveVotingAvailable() {
        let shouldStartAutoConfirm = !isGameInfoReceived

        isGameInfoReceived = true
        isVotingAvailable = true
        endedGameDate = nil

        if shouldStartAutoConfirm {
            startAutoConfirm()
        }

        provideViewModel()
    }

    func didReceiveVotingUnavailable(endedGameDate: Date?) {
        stopAutoConfirmTimer()
        isGameInfoReceived = true
        isVotingAvailable = false
        self.endedGameDate = endedGameDate
        provideViewModel()
    }
}

private extension GameReportPresenter {
    enum Constants {
        static let autoConfirmDuration = 8
    }

    func provideViewModel() {
        let viewModel = viewModelProvider.provideViewModel(
            votes: votes,
            confirmButtonState: confirmButtonState,
            isGameEnded: !isVotingAvailable,
            gameDate: endedGameDate
        )
        view?.didReceive(viewModel: viewModel)
    }

    func provideConfirmButtonState() {
        view?.didReceive(confirmButtonState: confirmButtonState)
    }

    func startAutoConfirm() {
        autoConfirmTimer.start(
            with: TimeInterval(Constants.autoConfirmDuration),
            runLoop: .main,
            mode: .common
        )
    }

    func updateAutoConfirmState(remainedInterval: TimeInterval) {
        let secondsRemaining = Int(ceil(remainedInterval))

        confirmButtonState = .autoConfirm(
            secondsRemaining: secondsRemaining,
            progress: autoConfirmProgressTarget(secondsRemaining: secondsRemaining)
        )
    }

    func cancelAutoConfirmForVoteChange() {
        stopAutoConfirmTimer()
        confirmButtonState = .confirm
        provideConfirmButtonState()
    }

    func stopAutoConfirmTimer() {
        autoConfirmTimer.stop()
    }

    func autoConfirmProgressTarget(secondsRemaining: Int) -> CGFloat {
        let elapsedSeconds = Constants.autoConfirmDuration - secondsRemaining + 1
        return CGFloat(elapsedSeconds) / CGFloat(Constants.autoConfirmDuration)
    }
}

extension GameReportPresenter: CountdownTimerDelegate {
    func didStart(with remainedInterval: TimeInterval) {
        updateAutoConfirmState(remainedInterval: remainedInterval)
    }

    func didCountdown(remainedInterval: TimeInterval) {
        updateAutoConfirmState(remainedInterval: remainedInterval)
        provideConfirmButtonState()
    }

    func didStop(with remainedInterval: TimeInterval) {
        guard remainedInterval <= 0 else {
            return
        }

        confirmButtonState = .confirming
        provideConfirmButtonState()
        interactor.reportCurrentVotes()
    }
}
