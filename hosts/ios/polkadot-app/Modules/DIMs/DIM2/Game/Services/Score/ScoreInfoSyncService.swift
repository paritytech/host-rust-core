import Foundation
import SubstrateSdk
import CommonService
import AsyncExtensions
import SubstrateStorageSubscription
import SubstrateStorageQuery
import Individuality

protocol ScoreInfoSyncServicing: ApplicationServiceProtocol {
    func observe() -> AnyAsyncSequence<ScoreInfo?>
    func setAccountOrPerson(_ accountOrPerson: GamePallet.AccountOrPerson)
}

protocol ScoreInfoSyncServiceObserving: AnyObject {
    func scoreInfoSubscriptionResultChanged(_ result: ScoreInfoSubscriptionResult)
}

final class ScoreInfoSyncService: BaseSyncService {
    private var accountOrPerson: GamePallet.AccountOrPerson?
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private weak var observer: ScoreInfoSyncServiceObserving?
    private let scoreInfoFactory: ScoreInfoMaking

    private var task: Task<Void, Never>?
    private let subject = AsyncCurrentValueSubject<ScoreInfo?>(nil)

    init(
        accountOrPerson: GamePallet.AccountOrPerson?,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        observer: ScoreInfoSyncServiceObserving?,
        scoreInfoFactory: ScoreInfoMaking = ScoreInfoFactory(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.accountOrPerson = accountOrPerson
        logger.debug("Initialized with type: \(String(describing: accountOrPerson?.rawTypeValue))")
        self.connection = connection
        self.runtimeService = runtimeService
        self.observer = observer
        self.scoreInfoFactory = scoreInfoFactory
        super.init(logger: logger)
    }

    override func performSyncUp() {
        guard let accountOrPerson else {
            return
        }

        task = Task {
            do {
                let stream = CallbackBatchStorageSubscription<ScoreInfoSubscriptionResult>.asyncStream(
                    requests: createRequests(for: accountOrPerson),
                    connection: connection,
                    runtimeService: runtimeService,
                    logger: logger
                )

                var syncData = ScoreInfoSyncData()

                logger.debug("Starting participant subscription")

                for try await subscriptionResult in stream {
                    guard !Task.isCancelled else {
                        return
                    }

                    syncData = syncData.applying(subscriptionResult)

                    let model = scoreInfoFactory.makeScoreInfo(
                        syncData: syncData
                    )

                    logger.debug("New model: \(String(describing: model))")

                    guard !Task.isCancelled else {
                        return
                    }

                    observer?.scoreInfoSubscriptionResultChanged(subscriptionResult)

                    subject.send(model)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                logger.error("Subscription failed: \(error)")
                complete(error)
            }
        }
    }

    override func stopSyncUp() {
        task?.cancel()
        task = nil
    }
}

extension ScoreInfoSyncService: ScoreInfoSyncServicing {
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

    func observe() -> AnyAsyncSequence<ScoreInfo?> {
        mutex.lock()

        defer {
            mutex.unlock()
        }

        return subject
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }
}

private extension ScoreInfoSyncService {
    func createRequests(for accountOrPerson: GamePallet.AccountOrPerson) -> [BatchStorageSubscriptionRequest] {
        let participantsRequest = BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: ScorePallet.participants,
                localKey: "",
                keyParamClosure: { [accountOrPerson] in accountOrPerson }
            ),
            mappingKey: ScoreInfoSubscriptionResult.Key.participant.rawValue
        )

        let personhoodThresholdRequest = BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: ScorePallet.personhoodThreshold,
                localKey: ""
            ),
            mappingKey: ScoreInfoSubscriptionResult.Key.personhoodThreshold.rawValue
        )

        return [participantsRequest, personhoodThresholdRequest]
    }
}
