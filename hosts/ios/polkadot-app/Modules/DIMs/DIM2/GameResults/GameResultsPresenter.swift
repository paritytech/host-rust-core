import Foundation

@MainActor
final class GameResultsPresenter {
    weak var view: GameResultsViewProtocol?

    private let wireframe: GameResultsWireframeProtocol
    private let interactor: GameResultsInteractorInputProtocol
    private let orchestrator: GameResultsOrchestrator
    private let sink: WebViewAttestationSink
    private let context: ReportSuccessContext

    private var lastInput: GameResultsInput?
    private var lastOutcome: GameOutcome?
    private var didFlushInitial = false
    private var isWebviewReady = false

    init(
        wireframe: GameResultsWireframeProtocol,
        interactor: GameResultsInteractorInputProtocol,
        orchestrator: GameResultsOrchestrator,
        sink: WebViewAttestationSink,
        context: ReportSuccessContext
    ) {
        self.wireframe = wireframe
        self.interactor = interactor
        self.orchestrator = orchestrator
        self.sink = sink
        self.context = context
    }
}

extension GameResultsPresenter: GameResultsPresenterProtocol {
    func setup() {
        Logger.shared
            .debug(
                "[GameDebug] presenter.setup → wireOrchestrator + orchestrator.start + interactor.start " +
                    "gameIndex=\(context.gameIndex)"
            )
        wireOrchestrator()
        orchestrator.start()
        interactor.start(context: context)
    }
}

extension GameResultsPresenter: GameResultsInteractorOutputProtocol {
    func didReceiveResults(_ input: GameResultsInput) {
        let isInitial = lastInput == nil
        lastInput = input
        Logger.shared
            .debug(
                "[GameDebug] presenter.didReceiveResults isInitial=\(isInitial) " +
                    "webviewReady=\(isWebviewReady) " +
                    "total=\(input.attestations.total) " +
                    "hashes=\(input.attestationHashes.count)"
            )
        guard isWebviewReady else {
            Logger.shared.debug("[GameDebug] presenter buffered input until flow.ready")
            return
        }
        deliverCurrent()
    }

    func didReceiveOutcome(_ outcome: GameOutcome) {
        lastOutcome = outcome
        Logger.shared
            .debug(
                "[GameDebug] presenter.didReceiveOutcome webviewReady=\(isWebviewReady) " +
                    "passed=\(outcome.passed) justBecameMember=\(outcome.justBecameMember) " +
                    "prize.present=\(outcome.prizeDraw != nil) claim.eligible=\(outcome.usernameClaim.eligible)"
            )
        guard isWebviewReady else {
            Logger.shared.debug("[GameDebug] presenter buffered outcome until flow.ready")
            return
        }
        deliverOutcome()
    }

    func didReceiveAttestation(hash: Data) {
        Logger.shared
            .debug(
                "[GameDebug] presenter.didReceiveAttestation hash=\(hash.toHex()) " +
                    "→ sink.push (webviewReady=\(isWebviewReady))"
            )
        sink.push(hash: hash)
    }
}

private extension GameResultsPresenter {
    func wireOrchestrator() {
        orchestrator.onReady = { [weak self] in
            guard let self else { return }
            Logger.shared.debug("[GameDebug] orchestrator.onReady — webview ready")
            isWebviewReady = true
            deliverCurrent()
            deliverOutcome()
        }
        orchestrator.onPrizeWon = { [weak self] in
            Logger.shared.debug("[GameDebug] orchestrator.onPrizeWon — triggering claim")
            self?.lastInput?.onPrizeClaim?()
        }
        orchestrator.onComplete = { [weak self] in
            guard let self else { return }
            Logger.shared.debug("[GameDebug] orchestrator.onComplete — closing module")
            interactor.stop()
            wireframe.close(view: view)
        }
        orchestrator.onDisplayNameRequested = { [weak self] in
            guard let self else { return }
            let displayName = lastInput?.member.displayName
            Logger.shared
                .debug("[GameDebug] orchestrator.onDisplayNameRequested storedDisplayName=\(displayName ?? "nil")")
            guard let displayName else { return }
            view?.deliverDisplayName(displayName)
        }
        orchestrator.onUsernameAvailabilityNeeded = { [weak self] name in
            Logger.shared.debug("[GameDebug] orchestrator.onUsernameAvailabilityNeeded name=\(name)")
            self?.resolveUsernameAvailability(name)
        }
    }

    func deliverCurrent() {
        guard let input = lastInput else {
            Logger.shared.debug("[GameDebug] presenter.deliverCurrent skipped — no lastInput")
            return
        }
        Logger.shared
            .debug(
                "[GameDebug] presenter.deliverCurrent → view.deliverInput " +
                    "didFlushInitial=\(didFlushInitial) hashes=\(input.attestationHashes.count)"
            )
        view?.deliverInput(input)
        if !didFlushInitial {
            didFlushInitial = true
            Logger.shared.debug("[GameDebug] presenter.deliverCurrent → sink.deliverInitialAttestations")
            sink.deliverInitialAttestations()
        }
    }

    func deliverOutcome() {
        guard let outcome = lastOutcome else {
            Logger.shared.debug("[GameDebug] presenter.deliverOutcome skipped — no outcome yet")
            return
        }
        Logger.shared.debug("[GameDebug] presenter.deliverOutcome → view.deliverOutcome")
        view?.deliverOutcome(outcome)
    }

    func resolveUsernameAvailability(_ name: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let availability = await interactor.resolveUsernameAvailability(name: name)
            Logger.shared.debug("[GameDebug] deliverUsernameAvailability \(availability) for name=\(name)")
            view?.deliverUsernameAvailability(availability, alternatives: nil)
        }
    }
}
