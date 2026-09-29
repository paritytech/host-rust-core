import Foundation
import CommonService
import SubstrateSdk
import SubstrateStorageSubscription

protocol GameStateTransition: BaseObservableStateStore<GameStateMachine.State> {
    func throttle()
}

// @unchecked Sendable: all mutable state confined to serial workQueue
final class GameStateMachine: BaseObservableStateStore<GameStateMachine.State>, @unchecked Sendable {
    private let infoSyncService: GameInfoSyncServicing
    private let timelineService: GameTimelineServicing

    private let workQueue: DispatchQueue

    private var info: GameInfo?
    private var timeIntervalSinceStart: TimeInterval?
    private var gameTask: Task<Void, Never>?

    private var switchedToFinishedState = false

    init(
        workQueue: DispatchQueue,
        infoSyncService: GameInfoSyncServicing,
        timelineService: GameTimelineServicing,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.workQueue = workQueue
        self.infoSyncService = infoSyncService
        self.timelineService = timelineService

        super.init(logger: logger)

        subscribeToInfo()
        subscribeToTimeline()
    }

    deinit {
        logger.debug("Deinit")
        gameTask?.cancel()
    }
}

extension GameStateMachine: GameStateTransition {
    func throttle() {
        gameTask?.cancel()
        timelineService.remove(observer: self)
    }
}

private extension GameStateMachine {
    func subscribeToInfo() {
        gameTask = Task { [weak self, infoSyncService, logger] in
            do {
                for try await info in infoSyncService.observe() {
                    logger.debug("Got new game info")

                    self?.workQueue.async {
                        self?.info = info
                        self?.updateState()
                    }
                }

                logger.debug("Game task completed")
            } catch {
                logger.error("Game info task failed: \(error)")
            }
        }
    }

    func subscribeToTimeline() {
        timelineService.add(
            observer: self,
            queue: workQueue
        ) { [weak self] _, timeIntervalSinceStart in
            self?.timeIntervalSinceStart = timeIntervalSinceStart
            self?.updateState()
        }
        timelineService.setup()
    }

    func updateState() {
        guard !switchedToFinishedState else {
            return
        }

        guard let info else {
            logger.debug("Missing game info")
            return
        }

        guard let timeIntervalSinceStart else {
            logger.debug("Missing time interval since start")
            return
        }

        logger.debug("timeIntervalSinceStart = \(timeIntervalSinceStart)")

        stateObservable.state = makeState(
            info: info,
            timeIntervalSinceStart: timeIntervalSinceStart
        )

        if case .finished = stateObservable.state {
            logger.debug("Switching to finished")
            switchedToFinishedState = true
        }
    }

    func makeState(
        info: GameInfo,
        timeIntervalSinceStart: TimeInterval
    ) -> State {
        let subroundsCount = makeSubroundsCount(info: info)

        guard timeIntervalSinceStart >= 0 else {
            let canPreconnect: Bool =
                if case .inProgress = info.state {
                    timeIntervalSinceStart >= -TimeIntervals.preconnect
                } else {
                    false
                }
            return .preparing(.init(
                gameDate: info.gameDate,
                subroundsCount: subroundsCount,
                preconnectPlayers: canPreconnect ? info.players(for: 0) : nil,
                preconnectGameIndex: canPreconnect ? info.index : nil
            ))
        }

        switch info.state {
        case .registration,
             .shuffle:
            return .preparing(.init(
                gameDate: info.gameDate,
                subroundsCount: subroundsCount,
                preconnectPlayers: nil,
                preconnectGameIndex: nil
            ))
        case let .inProgress(inProgressState):
            guard let input = makeInProgressInput(info: info) else {
                return .preparing(.init(
                    gameDate: info.gameDate,
                    subroundsCount: subroundsCount,
                    preconnectPlayers: nil,
                    preconnectGameIndex: nil
                ))
            }
            return makeState(
                subroundsCount: subroundsCount,
                timeIntervalSinceStart: timeIntervalSinceStart,
                inProgressInput: input,
                inProgressState: inProgressState,
                sortedRounds: info.sortedRounds
            )
        case .processing,
             .cancelling:
            return .finished(.init(
                gameIndex: info.index,
                subroundsCount: subroundsCount
            ))
        }
    }

    func makeInProgressInput(info: GameInfo) -> GameInProgressInput? {
        guard let gameDate = info.gameDate else {
            return nil
        }
        return GameInProgressInput(
            gameDate: gameDate,
            gameIndex: info.index,
            isReportSent: info.isReportSent
        )
    }

    func makeState(
        subroundsCount: Int,
        timeIntervalSinceStart: TimeInterval,
        inProgressInput: GameInProgressInput,
        inProgressState: GameInProgressState,
        sortedRounds: [GameRound]
    ) -> State {
        switch inProgressState {
        case .notRegistered:
            .preparing(.init(
                gameDate: inProgressInput.gameDate,
                subroundsCount: subroundsCount,
                preconnectPlayers: nil,
                preconnectGameIndex: nil
            ))
        case let .inProgress(_, gameplayGroupSize):
            if inProgressInput.isReportSent {
                .finished(.init(
                    gameIndex: inProgressInput.gameIndex,
                    subroundsCount: subroundsCount
                ))
            } else {
                makeState(
                    inProgressInput: inProgressInput,
                    gameplayGroupSize: gameplayGroupSize,
                    subroundsCount: subroundsCount,
                    timeIntervalSinceStart: timeIntervalSinceStart,
                    sortedRounds: sortedRounds
                )
            }
        }
    }

    func makeState(
        inProgressInput: GameInProgressInput,
        gameplayGroupSize: UInt,
        subroundsCount: Int,
        timeIntervalSinceStart: TimeInterval,
        sortedRounds: [GameRound]
    ) -> State {
        guard !sortedRounds.isEmpty else {
            return .preparing(.init(
                gameDate: inProgressInput.gameDate,
                subroundsCount: subroundsCount,
                preconnectPlayers: nil,
                preconnectGameIndex: nil
            ))
        }

        let roundDuration = Double(gameplayGroupSize)
            * TimeIntervals.hostingMinimumDuration
        let gameDuration = roundDuration * Double(sortedRounds.count)

        guard timeIntervalSinceStart < gameDuration else {
            return .finished(.init(
                gameIndex: inProgressInput.gameIndex,
                subroundsCount: subroundsCount
            ))
        }

        let roundIndex = makeStepIndex(
            start: 0,
            timeIntervalSinceStart: timeIntervalSinceStart,
            fullDuration: gameDuration,
            stepDuration: roundDuration
        )
        let roundStart = Double(roundIndex) * roundDuration

        guard !sortedRounds[roundIndex].players.isEmpty else {
            return .preparing(.init(
                gameDate: inProgressInput.gameDate,
                subroundsCount: subroundsCount,
                preconnectPlayers: nil,
                preconnectGameIndex: nil
            ))
        }

        return makeRoundState(
            sortedRounds: sortedRounds,
            timeIntervalSinceStart: timeIntervalSinceStart,
            input: .init(
                diff: timeIntervalSinceStart - roundStart,
                start: roundStart,
                duration: roundDuration,
                index: roundIndex,
                gameIndex: inProgressInput.gameIndex,
                gameDate: inProgressInput.gameDate,
                subroundsCount: subroundsCount
            )
        )
    }

    func makeRoundState(
        sortedRounds: [GameRound],
        timeIntervalSinceStart: TimeInterval,
        input: RoundStateInput
    ) -> State {
        let rawRound = sortedRounds[input.index]

        let hosting = makeHosting(
            timeIntervalSinceStart: timeIntervalSinceStart,
            rawRound: rawRound,
            roundStart: input.start,
            roundDuration: input.duration
        )

        return .round(
            Round(
                players: rawRound.players,
                preconnectPlayers: makePreconnectPlayers(
                    sortedRounds: sortedRounds,
                    input: input
                ),
                state: .hosting(hosting),
                roundIndex: input.index
            ),
            RoundsInfo(
                gameIndex: input.gameIndex,
                gameDate: input.gameDate,
                subroundsCount: input.subroundsCount,
                subroundIndex: makeSubroundIndex(
                    rawRounds: sortedRounds,
                    roundIndex: input.index,
                    hostIndex: hosting.hostIndex
                )
            )
        )
    }

    func makeHosting(
        timeIntervalSinceStart: TimeInterval,
        rawRound: GameRound,
        roundStart: TimeInterval,
        roundDuration: TimeInterval
    ) -> Hosting {
        let hostingDuration = roundDuration / Double(rawRound.players.count)
        let hostIndex = makeStepIndex(
            start: roundStart,
            timeIntervalSinceStart: timeIntervalSinceStart,
            fullDuration: roundDuration,
            stepDuration: hostingDuration
        )
        let hostingStart = Double(hostIndex) * hostingDuration
        let host = rawRound.players[hostIndex]
        let absoluteHostingStart = roundStart + hostingStart
        let absoluteHostingEnd = absoluteHostingStart + hostingDuration

        if absoluteHostingEnd - timeIntervalSinceStart <= TimeIntervals.hostingEnd {
            return .init(
                host: host,
                state: .end,
                hostIndex: hostIndex
            )
        }

        let diff = timeIntervalSinceStart - absoluteHostingStart

        switch diff {
        case ..<TimeIntervals.hostingGameplayDelay:
            return .init(
                host: host,
                state: .introduction,
                hostIndex: hostIndex
            )
        default:
            return .init(
                host: host,
                state: .gameplay(
                    left: hostingDuration - diff - TimeIntervals.hostingEnd,
                    total: hostingDuration - TimeIntervals.hostingGameplayOffset
                ),
                hostIndex: hostIndex
            )
        }
    }

    func makePreconnectPlayers(
        sortedRounds: [GameRound],
        input: RoundStateInput
    ) -> [AccountId]? {
        let nextRoundIndex = input.index + 1

        guard
            sortedRounds.count > nextRoundIndex,
            input.duration - input.diff < TimeIntervals.preconnect
        else {
            return nil
        }

        return sortedRounds[nextRoundIndex].players
    }

    func makeStepIndex(
        start: TimeInterval,
        timeIntervalSinceStart: TimeInterval,
        fullDuration: TimeInterval,
        stepDuration: TimeInterval
    ) -> Int {
        let end = start + fullDuration
        let range = start ... end

        assert(
            range.contains(timeIntervalSinceStart),
            "timeIntervalSinceStart is out of bounds"
        )

        let elapsed = timeIntervalSinceStart - start
        let index = Int(elapsed / stepDuration)

        return index
    }

    func makeSubroundsCount(info: GameInfo) -> Int {
        guard
            case let .inProgress(inProgressState) = info.state,
            case .inProgress = inProgressState
        else {
            return 0
        }
        return info.sortedRounds.reduce(into: 0) { result, round in
            result += round.players.count
        }
    }

    func makeSubroundIndex(
        rawRounds: [GameRound],
        roundIndex: Int,
        hostIndex: Int
    ) -> Int {
        var result = 0

        for (index, rawRound) in rawRounds.enumerated() {
            if index < roundIndex {
                result += rawRound.players.count
            } else if index == roundIndex {
                result += hostIndex
            } else {
                break
            }
        }

        return result
    }
}
