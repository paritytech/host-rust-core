import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import CommonService
import AsyncExtensions
import Operation_iOS
import Individuality

protocol GameHistorySyncServicing: ApplicationServiceProtocol {
    func observe() -> AnyAsyncSequence<GameHistory?>
    func setAccountOrPerson(_ accountOrPerson: GamePallet.AccountOrPerson)
    func gameDate(for index: GamePallet.GameIndex) async throws -> Date?
}

final class GameHistorySyncService: BaseSyncService {
    private var accountOrPerson: GamePallet.AccountOrPerson?
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let gameHistoryFactory: GameHistoryMaking
    private let operationFactory: GameHistoryOperationMaking

    private let subject = AsyncCurrentValueSubject<GameHistory?>(nil)
    private var task: Task<Void, Never>?

    init(
        accountOrPerson: GamePallet.AccountOrPerson?,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        gameHistoryFactory: GameHistoryMaking = GameHistoryFactory(),
        operationFactory: GameHistoryOperationMaking = GameHistoryOperationFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountOrPerson = accountOrPerson
        self.connection = connection
        self.runtimeService = runtimeService
        self.gameHistoryFactory = gameHistoryFactory
        self.operationFactory = operationFactory
        super.init(logger: logger)
    }

    override func performSyncUp() {
        guard let accountOrPerson else {
            return
        }

        task = Task {
            do {
                let requests = createRequests(for: accountOrPerson)

                let stream = CallbackBatchStorageSubscription<GameHistorySubscriptionResult>.asyncStream(
                    requests: requests,
                    connection: connection,
                    runtimeService: runtimeService,
                    logger: logger
                )

                var syncData = GameHistorySyncData()

                for try await result in stream {
                    guard !Task.isCancelled else {
                        return
                    }

                    let oldSyncData = syncData
                    syncData = syncData.applying(result)

                    let history = gameHistoryFactory.makeGameHistory(syncData: syncData)

                    let activeGameChanged = oldSyncData.game?.index != syncData.game?.index
                    let globalIndexChanged = oldSyncData.globalGameIndex != syncData.globalGameIndex
                    let firstGameChanged = oldSyncData.firstGame != syncData.firstGame
                    let shouldFetchActualGameDates = activeGameChanged || globalIndexChanged || firstGameChanged

                    if shouldFetchActualGameDates, let range = syncData.range {
                        let actualGameDates = try await fetchActualGameDates(with: range, at: result.blockHash)

                        logger.debug("Fetched actual game dates, count = \(actualGameDates.count)")

                        syncData = syncData.applying(actualGameDates)

                        let newHistory = gameHistoryFactory.makeGameHistory(syncData: syncData)

                        guard !Task.isCancelled else {
                            return
                        }

                        logger.debug("Changes: \(String(describing: newHistory))")

                        subject.send(newHistory)
                    } else {
                        guard !Task.isCancelled else {
                            return
                        }

                        logger.debug("Changes: \(String(describing: history))")

                        subject.send(history)
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                logger.error("Task failed: \(error)")
                complete(error)
            }
        }
    }

    override func stopSyncUp() {
        task?.cancel()
        task = nil
    }
}

extension GameHistorySyncService: GameHistorySyncServicing {
    func gameDate(for index: GamePallet.GameIndex) async throws -> Date? {
        if let cached = subject.value?.items.first(where: { $0.index == index })?.date {
            return cached
        }

        let dates = try await fetchActualGameDates(with: index ... index, at: nil)
        return dates[index]
    }

    func observe() -> AnyAsyncSequence<GameHistory?> {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        return subject
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }

    func setAccountOrPerson(_ accountOrPerson: GamePallet.AccountOrPerson) {
        mutex.lock()
        defer { mutex.unlock() }

        guard self.accountOrPerson != accountOrPerson else {
            return
        }

        self.accountOrPerson = accountOrPerson
        logger.debug("Switched to type: \(accountOrPerson.rawTypeValue)")

        guard isActive else {
            return
        }

        stopSyncUp()
        performSyncUp()
    }
}

// MARK: - Main subscription

private extension GameHistorySyncService {
    func createRequests(for accountOrPerson: GamePallet.AccountOrPerson) -> [BatchStorageSubscriptionRequest] {
        [
            createGlobalIndexRequest(),
            createAttendanceHistoryRequest(accountOrPerson: accountOrPerson),
            createPlayerRequest(accountOrPerson: accountOrPerson),
            createArchivedPlayerRequest(accountOrPerson: accountOrPerson),
            createGameRequest()
        ]
    }

    func createGlobalIndexRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: GamePallet.gameIndex,
                localKey: ""
            ),
            mappingKey: GameHistorySubscriptionResult.Key.globalGameIndex.rawValue
        )
    }

    func createAttendanceHistoryRequest(
        accountOrPerson: GamePallet.AccountOrPerson
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: GamePallet.playerAttendanceHistory,
                localKey: "",
                keyParamClosure: { [accountOrPerson] in accountOrPerson }
            ),
            mappingKey: GameHistorySubscriptionResult.Key.attendanceHistory.rawValue
        )
    }

    func createPlayerRequest(
        accountOrPerson: GamePallet.AccountOrPerson
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: GamePallet.players,
                localKey: "",
                keyParamClosure: { [accountOrPerson] in accountOrPerson }
            ),
            mappingKey: GameHistorySubscriptionResult.Key.player.rawValue
        )
    }

    func createArchivedPlayerRequest(
        accountOrPerson: GamePallet.AccountOrPerson
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: GamePallet.archivedPlayers,
                localKey: "",
                keyParamClosure: { [accountOrPerson] in accountOrPerson }
            ),
            mappingKey: GameHistorySubscriptionResult.Key.archivedPlayer.rawValue
        )
    }

    func createGameRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: GamePallet.game,
                localKey: ""
            ),
            mappingKey: GameHistorySubscriptionResult.Key.game.rawValue
        )
    }
}

private extension GameHistorySyncService {
    func fetchActualGameDates(
        with range: ClosedRange<GamePallet.GameIndex>,
        at blockHash: Data?
    ) async throws -> ActualGameDatesByIndex {
        let wrapper = operationFactory.fetchActualGameDates(
            with: range,
            connection: connection,
            runtimeService: runtimeService,
            blockHash: blockHash
        )

        let blockHashHex = blockHash.map { $0.toHex() } ?? ""
        logger.debug("Going to fetch actual game dates with \(range) on \(blockHashHex)")

        return try await wrapper.asyncExecute()
    }
}
