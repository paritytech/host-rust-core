import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import AsyncExtensions
import CommonService
import Individuality

protocol GameInfoSyncServicing: ApplicationServiceProtocol {
    func observe() -> AnyAsyncSequence<GameInfo?>
    func setAccountOrPerson(_ accountOrPerson: GamePallet.AccountOrPerson)
}

protocol GameInfoSyncServiceObserving: AnyObject {
    func gameInfoSubscriptionResultChanged(_ result: GameInfoSubscriptionResult)
}

final class GameInfoSyncService: BaseSyncService {
    private var accountOrPerson: GamePallet.AccountOrPerson?
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private weak var observer: GameInfoSyncServiceObserving?
    private let gameInfoFactory: GameInfoMaking
    private let operationFactory: GameInfoOperationMaking

    private var task: Task<Void, Never>?
    private let subject = AsyncCurrentValueSubject<GameInfo?>(nil)

    init(
        accountOrPerson: GamePallet.AccountOrPerson?,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        observer: GameInfoSyncServiceObserving?,
        gameInfoFactory: GameInfoMaking = GameInfoFactory(),
        operationFactory: GameInfoOperationMaking = GameInfoOperationFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountOrPerson = accountOrPerson
        self.connection = connection
        self.runtimeService = runtimeService
        self.observer = observer
        self.gameInfoFactory = gameInfoFactory
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

                let stream = CallbackBatchStorageSubscription<GameInfoSubscriptionResult>.asyncStream(
                    requests: requests,
                    connection: connection,
                    runtimeService: runtimeService,
                    logger: logger
                )

                var syncData = GameInfoSyncData()

                for try await result in stream {
                    guard !Task.isCancelled else {
                        return
                    }

                    observer?.gameInfoSubscriptionResultChanged(result)

                    syncData = syncData.applying(result)

                    let gameInfo = gameInfoFactory.makeGameInfo(syncData: syncData)

                    if
                        let playersByRound = try await fetchPlayersByRoundIfNeeded(
                            syncData: syncData,
                            gameInfo: gameInfo,
                            blockHash: result.blockHash
                        ) {
                        logger.debug("Fetched players by round")

                        syncData = syncData.applying(playersByRound)

                        let newGameInfo = gameInfoFactory.makeGameInfo(syncData: syncData)

                        guard !Task.isCancelled else {
                            return
                        }

                        subject.send(newGameInfo)
                    } else {
                        guard !Task.isCancelled else {
                            return
                        }

                        subject.send(gameInfo)
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

extension GameInfoSyncService: GameInfoSyncServicing {
    func observe() -> AnyAsyncSequence<GameInfo?> {
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

        defer {
            mutex.unlock()
        }

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

private extension GameInfoSyncService {
    func createRequests(for accountOrPerson: GamePallet.AccountOrPerson) -> [BatchStorageSubscriptionRequest] {
        [
            createGameRequest(),
            createPlayerRequest(accountOrPerson: accountOrPerson),
            createPlayerIndicesRequest(accountOrPerson: accountOrPerson)
        ]
    }

    func createGameRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: GamePallet.game,
                localKey: ""
            ),
            mappingKey: GameInfoSubscriptionResult.Key.game.rawValue
        )
    }

    func createPlayerRequest(accountOrPerson: GamePallet.AccountOrPerson) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: GamePallet.players,
                localKey: "",
                keyParamClosure: { [accountOrPerson] in accountOrPerson }
            ),
            mappingKey: GameInfoSubscriptionResult.Key.player.rawValue
        )
    }

    func createPlayerIndicesRequest(
        accountOrPerson: GamePallet.AccountOrPerson
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: GamePallet.playerToIndex,
                localKey: "",
                keyParamClosure: { [accountOrPerson] in accountOrPerson }
            ),
            mappingKey: GameInfoSubscriptionResult.Key.playerIndices.rawValue
        )
    }

    func fetchPlayersByRoundIfNeeded(
        syncData: GameInfoSyncData,
        gameInfo: GameInfo?,
        blockHash: Data?
    ) async throws -> PlayersByRound? {
        guard case .reporting = syncData.game?.state else {
            return nil
        }

        let indexToPlayerKeysByRound = gameInfoFactory.makeIndexToPlayerKeysByRound(
            syncData: syncData,
            gameInfo: gameInfo
        )

        let wrapper = operationFactory.fetchPlayersByRound(
            for: indexToPlayerKeysByRound,
            connection: connection,
            runtimeService: runtimeService,
            blockHash: blockHash
        )

        let blockHashHex = blockHash.map { $0.toHex() } ?? ""
        logger.debug("Going to fetch players by round on \(blockHashHex)")
        logger.debug(
            indexToPlayerKeysByRound
                .map { "Round \($0): \($1.map(\.playerIndex))" }
                .joined(separator: ", ")
        )

        return try await wrapper.asyncExecute()
    }
}
