import UIKit
import SubstrateSdk
import Operation_iOS
import OperationExt
import Individuality
import BackgroundExecution
import StructuredConcurrency

final class GameReportInteractor {
    weak var presenter: GameReportInteractorOutputProtocol?

    private let gameId: Game.Identifier
    private let infoSyncService: GameInfoSyncServicing
    private let historySyncService: GameHistorySyncServicing
    private let reportService: GameReportServicing
    private let voteService: GameVoteServicing
    private let dataProviderFactory: GameVoteDataProviderMaking
    private let personDataStore: DetermineStatePersonDataStore
    private let claimBeneficiary: AccountId
    private let claimUsesScoreAlias: Bool
    private let player: GamePallet.AccountOrPerson
    private let operationQueue: OperationQueue
    private let backgroundExecutor: BackgroundExecuting
    private let workQueue = DispatchQueue(label: "GameReportInteractor.workQueue")
    private let logger: LoggerProtocol

    private let cancellable = CancellableCallStore()

    private var votesProvider: StreamableProvider<GameVote>?
    private var votesByIdentifier = [String: GameVote]()

    private var gameInfo: GameInfo?
    private var gameTask: Task<Void, Never>?

    init(
        gameId: Game.Identifier,
        infoSyncService: GameInfoSyncServicing,
        historySyncService: GameHistorySyncServicing,
        reportService: GameReportServicing,
        personDataStore: DetermineStatePersonDataStore,
        claimBeneficiary: AccountId,
        claimUsesScoreAlias: Bool,
        player: GamePallet.AccountOrPerson,
        voteService: GameVoteServicing = GameVoteService(),
        dataProviderFactory: GameVoteDataProviderMaking = GameVoteDataProviderFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        backgroundExecutor: BackgroundExecuting,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.gameId = gameId
        self.infoSyncService = infoSyncService
        self.historySyncService = historySyncService
        self.reportService = reportService
        self.personDataStore = personDataStore
        self.claimBeneficiary = claimBeneficiary
        self.claimUsesScoreAlias = claimUsesScoreAlias
        self.player = player
        self.voteService = voteService
        self.dataProviderFactory = dataProviderFactory
        self.operationQueue = operationQueue
        self.backgroundExecutor = backgroundExecutor
        self.logger = logger
    }

    deinit {
        gameTask?.cancel()
    }
}

extension GameReportInteractor: GameReportInteractorInputProtocol {
    func setup() {
        reportService.setup()
        subscribeToGameVotes()
        subscribeToGameInfo()
    }

    func reportCurrentVotes() {
        guard gameInfo?.index == gameId.index, case .inProgress = gameInfo?.state else {
            logger
                .debug(
                    "[GameDebug] reportCurrentVotes blocked gameId=\(gameId.index) " +
                        "currentIndex=\(String(describing: gameInfo?.index)) " +
                        "state=\(String(describing: gameInfo?.state))"
                )
            return
        }

        guard !cancellable.hasCall else {
            logger.debug("[GameDebug] reportCurrentVotes blocked: already in flight")
            return
        }

        let gameSnapshot = gameContextSnapshot()
        let gameIndex = gameId.index
        let votesCount = votesByIdentifier.count
        logger
            .debug(
                "[GameDebug] reportCurrentVotes start gameIndex=\(gameIndex) votesCount=\(votesCount) " +
                    "snapshot.maxGroupSize=\(gameSnapshot.maxGroupSize) " +
                    "snapshot.playerCount=\(gameSnapshot.playerCount)"
            )

        Task { [weak self] in
            await markStallActivity("Reporting votes") {
                await self?.performReport(
                    gameIndex: gameIndex,
                    gameSnapshot: gameSnapshot
                )
            }
        }
    }

    func toggleVote(_ gameVote: GameVote) {
        Task { [voteService] in
            try await voteService.toggleVote(gameVote)
        }
    }
}

extension GameReportInteractor: GameVoteDataSubscribing, GameVoteDataHandling, AnyProviderAutoCleaning {
    var gameVoteDataProviderFactory: GameVoteDataProviderMaking {
        dataProviderFactory
    }

    func handleGameVotes(result: Result<[DataProviderChange<GameVote>], any Error>) {
        switch result {
        case let .success(changes):
            updateVotes(with: changes)
        case let .failure(error):
            logger.error("Did receive error: \(error)")
        }
    }
}

private extension GameReportInteractor {
    func performReport(
        gameIndex: GamePallet.GameIndex,
        gameSnapshot: GameContextSnapshot
    ) async {
        do {
            // swiftlint:disable closure_parameter_position
            try await backgroundExecutor.execute { [
                weak presenter,
                reportService,
                personDataStore,
                player,
                claimBeneficiary,
                claimUsesScoreAlias,
                logger
            ] in
                await presenter?.didReceive(isReportInProgress: true)

                let wasPerson = await MainActor.run {
                    personDataStore.currentState?.hasReachedPersonhood ?? false
                }
                logger.debug("[GameDebug] pre-report wasPerson=\(wasPerson)")

                logger.debug("[GameDebug] submitting report extrinsic gameIndex=\(gameIndex)")
                let result = try await reportService.reportVotesForCurrentGame()
                await presenter?.didReceive(isReportInProgress: false)

                switch result.status {
                case let .success(successExtrinsic):
                    logger
                        .debug(
                            "[GameDebug] report extrinsic SUCCESS " +
                                "blockHash=\(successExtrinsic.blockHash) " +
                                "extrinsicHash=\(successExtrinsic.extrinsicHash) " +
                                "gameIndex=\(gameIndex)"
                        )
                    let context = ReportSuccessContext(
                        gameIndex: gameIndex,
                        player: player,
                        reportBlockHash: try? Data(hexString: successExtrinsic.blockHash),
                        wasPersonBeforeReport: wasPerson,
                        gameSnapshot: gameSnapshot,
                        claimBeneficiary: claimBeneficiary,
                        claimUsesScoreAlias: claimUsesScoreAlias
                    )
                    await presenter?.didReportCurrentVotes(context: context)
                case let .failure(dispathError):
                    logger
                        .error(
                            "[GameDebug] report extrinsic FAILURE error=\(dispathError) gameIndex=\(gameIndex)"
                        )
                    await presenter?.didReceive(error: dispathError.error)
                }
            }
            // swiftlint:enable closure_parameter_position
        } catch {
            await presenter?.didReceive(isReportInProgress: false)
            logger.error("[GameDebug] report extrinsic THREW error=\(error) gameIndex=\(gameIndex)")
            await presenter?.didReceive(error: error)
        }
    }

    func subscribeToGameVotes() {
        clear(streamableProvider: &votesProvider)

        votesProvider = subscribeOnVisibleGameVotes(
            for: gameId.index,
            on: workQueue
        )
    }

    func subscribeToGameInfo() {
        gameTask?.cancel()
        gameTask = Task { [weak self, infoSyncService, logger] in
            do {
                for try await info in infoSyncService.observe() {
                    logger.debug("Got new game info")

                    await self?.updateGameInfo(info)
                }

                logger.debug("Game task completed")
            } catch {
                logger.error("Game info task failed: \(error)")
            }
        }
    }

    @MainActor
    func updateGameInfo(_ newInfo: GameInfo?) {
        gameInfo = newInfo

        let isCurrentGame = newInfo?.index == gameId.index
        let isVotingAvailable = isCurrentGame && newInfo?.state.isInProgress == true

        logger.debug(
            "[GameDebug] gate gameId=\(gameId.index) currentIndex=\(String(describing: newInfo?.index)) "
                + "state=\(String(describing: newInfo?.state)) " +
                "isCurrent=\(isCurrentGame) " +
                "votingAvailable=\(isVotingAvailable)"
        )

        if isVotingAvailable {
            presenter?.didReceiveVotingAvailable()
        } else if isCurrentGame {
            presenter?.didReceiveVotingUnavailable(endedGameDate: newInfo?.gameDate)
        } else {
            fetchEndedGameDate()
        }
    }

    func fetchEndedGameDate() {
        Task { [weak self, historySyncService, logger] in
            guard let self else { return }

            do {
                let date = try await historySyncService.gameDate(for: gameId.index)
                await presenter?.didReceiveVotingUnavailable(endedGameDate: date)
            } catch {
                logger.error("Failed to fetch ended game date: \(error)")
                await presenter?.didReceiveVotingUnavailable(endedGameDate: nil)
            }
        }
    }

    func gameContextSnapshot() -> GameContextSnapshot {
        let maxGroupSize = gameInfo?.maxGroupSize ?? 0
        let playerCount: UInt = {
            guard case let .inProgress(state) = gameInfo?.state,
                  case let .inProgress(count, _) = state
            else { return 0 }
            return UInt(count)
        }()
        return GameContextSnapshot(maxGroupSize: maxGroupSize, playerCount: playerCount)
    }

    func updateVotes(with changes: [DataProviderChange<GameVote>]) {
        votesByIdentifier = changes.mergeToDict(votesByIdentifier)

        let sortedVotes = Array(
            votesByIdentifier
                .values
                .sorted {
                    guard let lhs = $0.voteUpdateDate else {
                        return false
                    }
                    guard let rhs = $1.voteUpdateDate else {
                        return true
                    }
                    return lhs > rhs
                }
        )

        let voteDebug = sortedVotes.map {
            "id: \($0.accountId.toHex().prefix(8)), isPerson: \($0.isPerson)"
        }
        .sorted()
        .joined(separator: "\n")

        logger.debug("Votes results: \n\(voteDebug)")

        DispatchQueue.main.async { [weak self] in
            self?.presenter?.didReceive(votes: sortedVotes)
        }
    }
}
