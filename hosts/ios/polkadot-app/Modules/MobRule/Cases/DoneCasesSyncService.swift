import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import CommonService
import Individuality

protocol DoneCasesSyncObserver: AnyObject {
    func casesDidUpdate(with result: MobRulePallet.DoneCasesResult, blockHash: Data?)
    func casesSubscriptionFailed(with error: Error)
}

final class DoneCasesSyncService: BaseSyncService {
    private struct Observer {
        weak var value: DoneCasesSyncObserver?
    }

    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let workQueue: DispatchQueue
    private let operationQueue: OperationQueue
    private var observers = [ObjectIdentifier: Observer]()
    private var caseIndexes: [MobRulePallet.CaseIndex]
    private var subscription: CallbackBatchStorageSubscription<DoneCasesSubscriptionResult>?

    init(
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        observers: [DoneCasesSyncObserver],
        caseIndexes: [MobRulePallet.CaseIndex],
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        workQueue: DispatchQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.workQueue = workQueue
        self.operationQueue = operationQueue
        self.caseIndexes = caseIndexes

        super.init(logger: logger)
        observers.forEach { self.addObserver($0) }
    }

    override func performSyncUp() {
        subscription?.unsubscribe()

        subscription = CallbackBatchStorageSubscription(
            requests: caseIndexes.compactMap { try? createSubscriptionRequest(for: $0) },
            connection: connection,
            runtimeService: runtimeService,
            repository: nil,
            operationQueue: operationQueue,
            callbackQueue: workQueue
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(model):
                logger.debug("Cases update: \(model)")
                complete(nil)
                notifyObservers(for: model)
            case let .failure(error):
                logger.error("Cases subscription failed: \(error)")
                complete(error)
                notifyObservers(for: error)
            }
        }
        subscription?.subscribe()
    }

    override func stopSyncUp() {
        subscription?.unsubscribe()
        subscription = nil
    }
}

private extension DoneCasesSyncService {
    func addObserver(_ observer: DoneCasesSyncObserver) {
        observers[ObjectIdentifier(observer)] = Observer(value: observer)
    }

    func removeObserver(_ observer: DoneCasesSyncObserver) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
    }

    func notifyObservers(for result: DoneCasesSubscriptionResult) {
        observers.values.forEach {
            $0.value?.casesDidUpdate(with: result.cases, blockHash: result.blockHash)
        }
    }

    func notifyObservers(for error: Error) {
        observers.values.forEach { $0.value?.casesSubscriptionFailed(with: error) }
    }

    func createSubscriptionRequest(
        for caseIndex: MobRulePallet.CaseIndex
    ) throws -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: MobRulePallet.doneCasesPath,
                localKey: "",
                keyParamClosure: {
                    StringScaleMapper(value: caseIndex)
                }
            ),
            mappingKey: String(caseIndex)
        )
    }
}
