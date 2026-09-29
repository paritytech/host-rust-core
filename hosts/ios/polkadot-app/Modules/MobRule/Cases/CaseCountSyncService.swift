import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import CommonService
import Individuality

protocol CaseCountSyncObserver: AnyObject {
    func caseCountDidUpdate(with count: MobRulePallet.CaseIndex)
    func caseCountSubscriptionFailed(with error: Error)
}

final class CaseCountSyncService: BaseSyncService {
    private struct Observer {
        weak var value: CaseCountSyncObserver?
    }

    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let workQueue: DispatchQueue
    private let operationQueue: OperationQueue
    private var observers = [ObjectIdentifier: Observer]()
    private var subscription: CallbackBatchStorageSubscription<CaseCountSubscriptionResult>?

    init(
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        observers: [CaseCountSyncObserver],
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        workQueue: DispatchQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
        self.workQueue = workQueue
        self.operationQueue = operationQueue

        super.init(logger: logger)
        observers.forEach { self.addObserver($0) }
    }

    override func performSyncUp() {
        let request = createSubscriptionRequest()

        subscription?.unsubscribe()

        subscription = CallbackBatchStorageSubscription(
            requests: [
                request
            ],
            connection: connection,
            runtimeService: runtimeService,
            repository: nil,
            operationQueue: operationQueue,
            callbackQueue: workQueue
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(model):
                logger.debug("Case count update: \(model)")
                complete(nil)
                notifyObservers(for: model)
            case let .failure(error):
                logger.error("Case count subscription failed: \(error)")
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

private extension CaseCountSyncService {
    func addObserver(_ observer: CaseCountSyncObserver) {
        observers[ObjectIdentifier(observer)] = Observer(value: observer)
    }

    func removeObserver(_ observer: CaseCountSyncObserver) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
    }

    func notifyObservers(for result: CaseCountSubscriptionResult) {
        guard let updatedCaseCount = result.count else { return }
        observers.values.forEach { $0.value?.caseCountDidUpdate(with: updatedCaseCount) }
    }

    func notifyObservers(for error: Error) {
        observers.values.forEach { $0.value?.caseCountSubscriptionFailed(with: error) }
    }

    func createSubscriptionRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: MobRulePallet.caseCountPath,
                localKey: ""
            ),
            mappingKey: CaseCountSubscriptionResult.Key.count.rawValue
        )
    }
}
