import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import SubstrateStorageQuery
import CommonService
import AsyncExtensions
import Operation_iOS
import Individuality

protocol GameScheduleSyncServicing: ApplicationServiceProtocol {
    func observe() -> AnyAsyncSequence<GameSchedule?>
}

final class GameScheduleSyncService: BaseSyncService {
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let gameScheduleFactory: GameScheduleMaking

    private let subject = AsyncCurrentValueSubject<GameSchedule?>(nil)
    private var task: Task<Void, Never>?

    init(
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        gameScheduleFactory: GameScheduleMaking = GameScheduleFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.gameScheduleFactory = gameScheduleFactory
        super.init(logger: logger)
    }

    override func performSyncUp() {
        task = Task {
            do {
                let requests = try await createRequests()

                guard !Task.isCancelled else {
                    return
                }

                let stream = CallbackBatchStorageSubscription<GameScheduleSubscriptionResult>.asyncStream(
                    requests: requests,
                    connection: connection,
                    runtimeService: runtimeService,
                    logger: logger
                )

                var syncData = GameScheduleSyncData()

                for try await result in stream {
                    guard !Task.isCancelled else {
                        return
                    }

                    syncData = syncData.applying(result)

                    if syncData.constantDurationValues == nil {
                        let constantDurationValues = try await fetchConstantDurationValues()
                        syncData = syncData.applying(constantDurationValues: constantDurationValues)
                    }

                    let schedule = gameScheduleFactory.makeGameSchedule(syncData: syncData)

                    guard !Task.isCancelled else {
                        return
                    }

                    logger.debug("Changes: \(String(describing: schedule))")

                    subject.send(schedule)
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

extension GameScheduleSyncService: GameScheduleSyncServicing {
    func observe() -> AnyAsyncSequence<GameSchedule?> {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        return subject.removeDuplicates().eraseToAnyAsyncSequence()
    }
}

private extension GameScheduleSyncService {
    func fetchConstantDurationValues() async throws -> GamePallet.PhaseDurationValues {
        logger.debug("Going to fetch constant duration values")

        let codingFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()
        let constOperation = StorageConstantOperation<GamePallet.PhaseDurationValues>(
            path: GamePallet.defaultPhaseDurations,
            fallbackValue: nil
        )

        constOperation.codingFactory = codingFactory

        let constValue = try await constOperation.asyncExecute()

        logger.debug("Fetched constant duration values: \(constValue)")

        return constValue
    }

    func createRequests() async throws -> [BatchStorageSubscriptionRequest] {
        let hasTestnetStorage = try await checkHasTestnetStorage()

        if hasTestnetStorage {
            return [
                createGameSchedulesRequest(),
                createTestnetDurationValuesRequest()
            ]
        } else {
            return [
                createGameSchedulesRequest()
            ]
        }
    }

    func createGameSchedulesRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: GamePallet.gameSchedules,
                localKey: ""
            ),
            mappingKey: GameScheduleSubscriptionResult.Key.gameSchedules.rawValue
        )
    }

    func createTestnetDurationValuesRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: GamePallet.testnetPhaseDurations,
                localKey: ""
            ),
            mappingKey: GameScheduleSubscriptionResult.Key.testnetDurationValues.rawValue
        )
    }

    func checkHasTestnetStorage() async throws -> Bool {
        let codingFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()
        let hasStorage = codingFactory.hasStorage(for: GamePallet.testnetPhaseDurations)

        logger.debug("Has testnet storage = \(hasStorage)")

        return hasStorage
    }
}
