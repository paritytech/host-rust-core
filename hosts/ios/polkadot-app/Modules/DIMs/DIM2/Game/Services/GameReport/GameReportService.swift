import Foundation
import Operation_iOS
import SubstrateSdk
import CommonService
import ExtrinsicService
import Individuality

protocol GameReportServicing: ApplicationServiceProtocol {
    func reportVotesForCurrentGame() async throws -> ExtrinsicMonitorSubmission
}

final class GameReportService: @unchecked Sendable {
    private let localPlayerId: AccountId
    private let registeredSource: People.RegisteredSource?
    private let infoSyncService: GameInfoSyncServicing
    private let submitReportService: GameSubmitReportServicing
    private let repository: AnyDataProviderRepository<GameVote>
    private let operationQueue: OperationQueue
    private let gameDashboardTelemetry: GameDashboardTelemetryServicing?
    private let logger: LoggerProtocol
    private let workQueue = DispatchQueue(label: "GameReportService.workQueue")

    private var gameToReport: GameInfo?
    private var gameTask: Task<Void, Never>?

    init(
        localPlayerId: AccountId,
        registeredSource: People.RegisteredSource?,
        infoSyncService: GameInfoSyncServicing,
        submitReportService: GameSubmitReportServicing,
        repositoryFactory: GameVoteRepositoryMaking = GameVoteRepositoryFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        gameDashboardTelemetry: GameDashboardTelemetryServicing? = nil,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.localPlayerId = localPlayerId
        self.registeredSource = registeredSource
        self.infoSyncService = infoSyncService
        self.submitReportService = submitReportService
        repository = repositoryFactory.createRepository(forFilter: nil)
        self.operationQueue = operationQueue
        self.gameDashboardTelemetry = gameDashboardTelemetry
        self.logger = logger
    }
}

extension GameReportService: GameReportServicing {
    enum ReportError: Error {
        case noGameToReport
    }

    func setup() {
        gameTask = Task { [weak self, infoSyncService, logger] in
            do {
                for try await info in infoSyncService.observe() {
                    logger.debug("Got new game info")

                    self?.workQueue.async {
                        self?.handleGameInfo(info)
                    }
                }

                logger.debug("Game task completed")
            } catch {
                logger.error("Game info task failed: \(error)")
            }
        }
    }

    func throttle() {
        gameTask?.cancel()
    }

    func reportVotesForCurrentGame() async throws -> ExtrinsicMonitorSubmission {
        let gameInfoOperation = gameToReportOperation()
        let gameToReport = try await gameInfoOperation.asyncExecute()

        guard
            case let .inProgress(inProgressState) = gameToReport.state,
            case .inProgress = inProgressState
        else {
            throw ReportError.noGameToReport
        }

        var fullReport = GamePallet.FullReport()
        var telemetryRounds: [[(peer: AccountId, verdict: GameDashboardVerdict)]] = []

        for round in gameToReport.sortedRounds {
            var roundReports = [GamePallet.Report]()
            var telemetryRound: [(peer: AccountId, verdict: GameDashboardVerdict)] = []

            for player in round.players where player != localPlayerId {
                let fetchVoteOperation = repository.fetchOperation(by: {
                    GameVote.makeIdentifier(gameIndex: gameToReport.index, player: player)
                }, options: .init())

                let vote = try await fetchVoteOperation.asyncExecute()

                let report: GamePallet.Report =
                    if let vote, vote.voteCounter > 0 {
                        .person
                    } else {
                        .notPerson
                    }

                let verdict: GameDashboardVerdict =
                    if let vote, vote.voteCounter > 0 {
                        .person
                    } else {
                        .notperson
                    }

                roundReports.append(report)
                telemetryRound.append((peer: player, verdict: verdict))
            }

            fullReport.append(roundReports)
            telemetryRounds.append(telemetryRound)
        }

        logger.debug("Full report to send: \(fullReport)")

        let submitWrapper = submitReportService.submitReport(
            with: { fullReport },
            usesScoreAlias: registeredSource?.isNotGameRecognizedPerson == true
        )

        let submission = try await submitWrapper.asyncExecute()

        gameDashboardTelemetry?.sendEnd(
            localAccount: localPlayerId,
            roundsReports: telemetryRounds
        )

        return submission
    }
}

private extension GameReportService {
    func handleGameInfo(_ gameInfo: GameInfo?) {
        guard
            let gameInfo,
            gameInfo.readyToReport
        else {
            gameToReport = nil
            return
        }
        gameToReport = gameInfo
    }

    func gameToReportOperation() -> AsyncClosureOperation<GameInfo> {
        AsyncClosureOperation { [weak self] completion in
            guard let self else {
                completion(.failure(ReportError.noGameToReport))
                return
            }
            workQueue.async {
                if let gameToReport = self.gameToReport {
                    completion(.success(gameToReport))
                } else {
                    completion(.failure(ReportError.noGameToReport))
                }
            }
        }
    }
}

private extension GameInfo {
    var readyToReport: Bool {
        guard
            case let .inProgress(inProgressState) = state,
            case .inProgress = inProgressState,
            !sortedRounds.isEmpty,
            !isReportSent
        else {
            return false
        }
        return true
    }
}
