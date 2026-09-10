import Foundation
import Operation_iOS
import CommonService
import SubstrateStorageSubscription
import SubstrateSdk
import Individuality
import ChainRegistry

protocol TattooSelectionSyncServiceObserver {
    func tattooSelectionStateChanged(by change: TattooSelectionStateChange)
}

final class TattooSelectionSyncService: BaseSyncService {
    let chainId: ChainModel.Id
    let accountId: AccountId
    let connection: JSONRPCEngine
    let runtimeService: RuntimeCodingServiceProtocol
    let workQueue: DispatchQueue
    let operatonQueue: OperationQueue
    let observers: [TattooSelectionSyncServiceObserver]

    private var subscription: CallbackBatchStorageSubscription<TattooSelectionStateChange>?

    init(
        chainId: ChainModel.Id,
        accountId: AccountId,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        observers: [TattooSelectionSyncServiceObserver],
        operatonQueue: OperationQueue,
        workQueue: DispatchQueue,
        logger: LoggerProtocol
    ) {
        self.chainId = chainId
        self.accountId = accountId
        self.connection = connection
        self.runtimeService = runtimeService
        self.workQueue = workQueue
        self.operatonQueue = operatonQueue
        self.observers = observers

        super.init(logger: logger)
    }

    private func createCandidatesRequest(for accountId: AccountId) throws -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: ProofOfInkPallet.candidatesPath,
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: accountId) }
            ),
            mappingKey: TattooSelectionStateChange.Key.candidate.rawValue
        )
    }

    private func createAccountRequest(for accountId: AccountId) throws -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: SystemPallet.accountPath,
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: accountId) }
            ),
            mappingKey: TattooSelectionStateChange.Key.account.rawValue
        )
    }

    private func createNextPeopleIdRequest() throws -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: PeoplePallet.nextPeopleIdPath,
                localKey: ""
            ),
            mappingKey: TattooSelectionStateChange.Key.nextPersonalId.rawValue
        )
    }

    private func notifyObservers(for change: TattooSelectionStateChange) {
        observers.forEach { $0.tattooSelectionStateChanged(by: change) }
    }

    override func performSyncUp() {
        do {
            let candidatesRequest = try createCandidatesRequest(for: accountId)
            let accountRequest = try createAccountRequest(for: accountId)
            let nextPeopleIdRequest = try createNextPeopleIdRequest()

            subscription?.unsubscribe()

            subscription = CallbackBatchStorageSubscription(
                requests: [
                    candidatesRequest,
                    accountRequest,
                    nextPeopleIdRequest
                ],
                connection: connection,
                runtimeService: runtimeService,
                repository: nil,
                operationQueue: operatonQueue,
                callbackQueue: workQueue
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
        } catch {
            completeImmediate(error)
        }
    }

    override func stopSyncUp() {
        subscription?.unsubscribe()
        subscription = nil
    }
}
