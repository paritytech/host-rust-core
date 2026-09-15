import Foundation
import AsyncExtensions
import Individuality
import PolkadotUI

// @unchecked Sendable: all mutable state confined to serial workQueue
final class DIM2GameWidgetProvider: @unchecked Sendable {
    private let flowState: DIM2SharedFlowStateProtocol
    private weak var wireframe: WeeklyGameWireframeProtocol?
    private let logger: LoggerProtocol
    private let workQueue = DispatchQueue(label: "DIM2GameWidgetProvider.gameState")
    private let widgetSubject = AsyncCurrentValueSubject<(any HashableContentConfiguration)?>(nil)

    private var gameStateTransition: GameStateTransition?
    private var gameInfoTask: Task<Void, Never>?
    private var latestGameInfo: GameInfo?
    private var latestGameState: GameStateMachine.State?
    private var autoOpenRequestedGameIndex: GamePallet.GameIndex?
    private var isObserving = false

    init(
        flowState: DIM2SharedFlowStateProtocol,
        wireframe: WeeklyGameWireframeProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.flowState = flowState
        self.wireframe = wireframe
        self.logger = logger
    }

    deinit {
        stopObservingGame()
    }

    func setup() {
        startObservingIfNeeded()
    }
}

extension DIM2GameWidgetProvider: ChatExtensionWidgetProvidable {
    func widgetConfigurationStream() async throws -> AnyAsyncSequence<(any HashableContentConfiguration)?> {
        widgetSubject.eraseToAnyAsyncSequence()
    }
}

private extension DIM2GameWidgetProvider {
    func startObservingIfNeeded() {
        guard !isObserving else {
            return
        }

        isObserving = true
        observeGameInfo(flowState.gameSyncService)
        startObservingGameState()
    }

    func startObservingGameState() {
        let gameStateTransition = makeGameStateTransition()
        self.gameStateTransition = gameStateTransition

        gameStateTransition.add(
            observer: self,
            queue: workQueue
        ) { [weak self] _, gameState in
            guard let self else {
                return
            }

            latestGameState = gameState
            emitWidgetState()
            autoOpenGameIfNeeded()
        }
    }

    func observeGameInfo(_ gameInfoService: GameInfoSyncServicing) {
        gameInfoTask = Task { [weak self, gameInfoService] in
            do {
                for try await gameInfo in gameInfoService.observe() {
                    self?.workQueue.async {
                        let previousGameIndex = self?.latestGameInfo?.index
                        self?.latestGameInfo = gameInfo

                        if let newGameIndex = gameInfo?.index {
                            self?.restartGameStateTransitionIfNeeded(
                                previousGameIndex: previousGameIndex,
                                newGameIndex: newGameIndex
                            )
                        }

                        self?.emitWidgetState()
                        self?.autoOpenGameIfNeeded()
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.logger.error("Game widget info subscription failed: \(error)")
            }
        }
    }

    func makeGameStateTransition() -> GameStateTransition {
        GameStateMachine(
            workQueue: workQueue,
            infoSyncService: flowState.gameSyncService,
            timelineService: GameTimelineService(
                workQueue: workQueue,
                infoSyncService: flowState.gameSyncService,
                synchronizedTimeService: SynchronizedTimeService()
            )
        )
    }

    func stopObservingGame() {
        gameInfoTask?.cancel()
        gameInfoTask = nil
        latestGameInfo = nil

        gameStateTransition?.remove(observer: self)
        gameStateTransition?.throttle()
        gameStateTransition = nil
        latestGameState = nil
        autoOpenRequestedGameIndex = nil

        isObserving = false
    }

    func restartGameStateTransitionIfNeeded(
        previousGameIndex: GamePallet.GameIndex?,
        newGameIndex: GamePallet.GameIndex
    ) {
        guard
            let previousGameIndex,
            previousGameIndex != newGameIndex
        else {
            return
        }

        gameStateTransition?.remove(observer: self)
        gameStateTransition?.throttle()
        gameStateTransition = nil
        latestGameState = nil
        autoOpenRequestedGameIndex = nil
        startObservingGameState()
    }

    func emitWidgetState() {
        let pillState = GameRoomPillState.resolve(
            gameInfo: latestGameInfo,
            gameTimelineState: latestGameState
        )

        guard let pillState else {
            widgetSubject.send(nil)
            return
        }

        widgetSubject.send(makeConfiguration(for: pillState))
    }

    func makeConfiguration(for pillState: GameRoomPillState) -> any HashableContentConfiguration {
        GameRoomPillConfiguration(
            content: makeContent(for: pillState),
            onTap: { [weak wireframe] in
                Task { @MainActor in
                    wireframe?.openCurrentGame()
                }
            }
        )
    }

    func makeContent(for pillState: GameRoomPillState) -> GameRoomPillViewModel.Content {
        switch pillState {
        case let .starting(gameDate):
            .waiting(gameDate: gameDate)
        case let .live(currentRound, totalRounds):
            .live(
                .init(
                    currentRound: currentRound,
                    totalRounds: totalRounds
                )
            )
        case .finished:
            .finished
        }
    }

    func autoOpenGameIfNeeded() {
        guard
            let gameInfo = latestGameInfo,
            gameInfo.isRegistered,
            !gameInfo.isReportSent,
            autoOpenRequestedGameIndex != gameInfo.index,
            case .round = latestGameState
        else {
            return
        }

        autoOpenRequestedGameIndex = gameInfo.index

        Task { @MainActor [weak wireframe] in
            wireframe?.openCurrentGame()
        }
    }
}
