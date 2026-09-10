import BulletinChain
import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import CommonService

protocol TattooUploadingBulletInSyncObserver {
    func tattooUploadingBulletInSyncChanged(by change: TattooUploadingBulletInSyncChange)
}

final class TattooUploadingBulletInSyncService: BaseSyncService {
    let accountId: AccountId
    let connection: JSONRPCEngine
    let runtimeService: RuntimeCodingServiceProtocol
    let processingQueue: DispatchQueue
    let operationQueue: OperationQueue
    let observers: [TattooUploadingBulletInSyncObserver]

    private var subscription: CallbackBatchStorageSubscription<TattooUploadingBulletInSyncChange>?

    init(
        accountId: AccountId,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        observers: [TattooUploadingBulletInSyncObserver],
        operationQueue: OperationQueue,
        processingQueue: DispatchQueue,
        logger: LoggerProtocol
    ) {
        self.accountId = accountId
        self.connection = connection
        self.runtimeService = runtimeService
        self.observers = observers
        self.processingQueue = processingQueue
        self.operationQueue = operationQueue

        super.init(logger: logger)
    }

    private func createAuthorizationsRequest(for accountId: AccountId) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: TransactionStoragePallet.authorizationsPath,
                localKey: "",
                keyParamClosure: { TransactionStoragePallet.AuthorizationScope.account(accountId) }
            ),
            mappingKey: TattooUploadingBulletInSyncChange.Key.authorizations.rawValue
        )
    }

    private func createBlockNumberRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: SystemPallet.blockNumberPath,
                localKey: ""
            ),
            mappingKey: TattooUploadingBulletInSyncChange.Key.blockNumber.rawValue
        )
    }

    private func notifyObservers(for change: TattooUploadingBulletInSyncChange) {
        observers.forEach { $0.tattooUploadingBulletInSyncChanged(by: change) }
    }

    override func performSyncUp() {
        subscription?.unsubscribe()

        subscription = CallbackBatchStorageSubscription(
            requests: [
                createAuthorizationsRequest(for: accountId),
                createBlockNumberRequest()
            ],
            connection: connection,
            runtimeService: runtimeService,
            repository: nil,
            operationQueue: operationQueue,
            callbackQueue: processingQueue
        ) { [weak self] result in
            switch result {
            case let .success(model):
                self?.logger.debug("Changes: \(model)")

                self?.complete(nil)

                self?.notifyObservers(for: model)
            case let .failure(error):
                self?.logger.error("Subscription failed: \(error)")

                self?.complete(error)
            }
        }

        subscription?.subscribe()
    }

    override func stopSyncUp() {
        subscription?.unsubscribe()
        subscription = nil
    }
}
