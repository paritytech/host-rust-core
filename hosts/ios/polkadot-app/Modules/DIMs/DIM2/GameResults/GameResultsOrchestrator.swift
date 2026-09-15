import UIKit

// Drives the game-results bridge lifecycle:
//   1. Logs JS console output forwarded through the bridge.
//   2. Fires callbacks for prize claim, username claim, completion.
//   3. Forwards display-name requests to native.

final class GameResultsOrchestrator {
    private let bridge: GameResultsBridge
    private let logger: LoggerProtocol

    var onReady: (() -> Void)?
    var onPrizeWon: (() -> Void)?
    var onUsernameClaimRequested: (() -> Void)?
    var onDisplayNameRequested: (() -> Void)?
    var onUsernameAvailabilityNeeded: ((String) -> Void)?
    var onError: ((_ phase: String, _ detail: String?) -> Void)?
    var onComplete: (() -> Void)?

    private var task: Task<Void, Never>?

    init(
        bridge: GameResultsBridge,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.bridge = bridge
        self.logger = logger
    }

    deinit {
        task?.cancel()
    }

    func start() {
        logger.debug("[GameDebug] orchestrator.start — subscribing to bridge events")
        task?.cancel()
        task = Task { [bridge, weak self] in
            for await event in bridge.events {
                guard let self else { return }
                handle(event)
            }
            Logger.shared.debug("[GameDebug] orchestrator event stream ended")
        }
    }
}

private extension GameResultsOrchestrator {
    // swiftlint:disable:next cyclomatic_complexity
    func handle(_ event: GameResultsInboundEvent) {
        logger.debug("[GameDebug] webview→app event=\(event)")
        switch event {
        case .ready:
            logger.debug("[GameDebug] flow.ready — webview ready to receive input")
            DispatchQueue.main.async { [weak self] in self?.onReady?() }
        case .resultsShown:
            logger.debug("[GameDebug] flow.results_shown — webview has rendered initial results screen")
        case .prizeDrawStarted:
            logger.debug("[GameDebug] flow.prize_draw_started — prize draw animation started")
        case let .prizeDrawComplete(won):
            logger.debug("[GameDebug] flow.prize_draw_complete won=\(won)")
            if won {
                logger.debug("[GameDebug] prize was won — invoking onPrizeWon callback")
                DispatchQueue.main.async { [weak self] in self?.onPrizeWon?() }
            }
        case let .nftRevealStarted(count):
            logger.debug("[GameDebug] flow.nft_reveal_started count=\(count)")
        case .nftRevealComplete:
            logger.debug("[GameDebug] flow.nft_reveal_complete — all NFT cards revealed")
        case .usernameClaimRequested:
            logger.debug("[GameDebug] flow.username_claim_requested — user tapped claim username")
            DispatchQueue.main.async { [weak self] in self?.onUsernameClaimRequested?() }
        case .requestDisplayName:
            logger.debug("[GameDebug] flow.request_display_name — webview asked for stored display name")
            DispatchQueue.main.async { [weak self] in self?.onDisplayNameRequested?() }
        case let .usernameAvailabilityNeeded(name):
            logger.debug("[GameDebug] flow.username_availability_needed name='\(name)'")
            DispatchQueue.main.async { [weak self] in self?.onUsernameAvailabilityNeeded?(name) }
        case let .error(phase, detail):
            logger.error("[GameDebug] flow.error phase=\(phase) detail=\(detail ?? "nil")")
            DispatchQueue.main.async { [weak self] in self?.onError?(phase, detail) }
        case .complete:
            logger.debug("[GameDebug] flow.complete — webview signaled completion, invoking onComplete")
            DispatchQueue.main.async { [weak self] in self?.onComplete?() }
        case let .log(level, message):
            logger.debug("[GameDebug][JS] \(level ?? "log"): \(message)")
        }
    }
}
