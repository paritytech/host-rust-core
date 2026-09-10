import Foundation
import Foundation_iOS
import Operation_iOS
import SubstrateSdk
import CommonService
import SubstrateStorageSubscription
import KeyDerivation
import Individuality
import ChainRegistry

protocol DetermineStateSyncServiceObserver: AnyObject {
    func determineStateSyncChanged(by change: DetermineStateSync.MainChange)
    func determineStateSyncChanged(by change: DetermineStateSync.PersonChange)
}

final class DetermineStateSyncService: BaseSyncService {
    let walletAccountId: AccountId
    let candidateAccountId: AccountId
    let mobRuleAccountId: AccountId
    let scoreAccountId: AccountId
    let resourcesAccountId: AccountId
    let memberKey: BandersnatchPubKey
    let chainId: ChainModel.Id
    let chainRegistry: ChainRegistryProtocol
    let proccessingQueue: DispatchQueue
    let operationQueue: OperationQueue
    private let observers: [WeakWrapper]

    private var mainSubscription: CallbackBatchStorageSubscription<
        DetermineStateSync.MainChange
    >?

    private var personSubscription: CallbackBatchStorageSubscription<
        DetermineStateSync.PersonChange
    >?

    private var personId: PeoplePallet.PersonalId?
    private var chainResolutionStore = CancellableCallStore()

    init(
        walletAccountId: AccountId,
        candidateAccountId: AccountId,
        mobRuleAccountId: AccountId,
        scoreAccountId: AccountId,
        resourcesAccountId: AccountId,
        memberKey: BandersnatchPubKey,
        chainId: ChainModel.Id,
        chainRegistry: ChainRegistryProtocol,
        observers: [DetermineStateSyncServiceObserver],
        operationQueue: OperationQueue,
        proccessingQueue: DispatchQueue,
        logger: LoggerProtocol
    ) {
        self.walletAccountId = walletAccountId
        self.candidateAccountId = candidateAccountId
        self.mobRuleAccountId = mobRuleAccountId
        self.scoreAccountId = scoreAccountId
        self.resourcesAccountId = resourcesAccountId
        self.memberKey = memberKey
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.observers = observers.map { .init(target: $0) }
        self.proccessingQueue = proccessingQueue
        self.operationQueue = operationQueue

        super.init(logger: logger)
    }

    override func performSyncUp() {
        performMainSyncUp()
    }

    override func stopSyncUp() {
        chainResolutionStore.cancel()

        mainSubscription?.unsubscribe()
        mainSubscription = nil

        cancelPersonSubscription()
    }
}

// MARK: - Main sync up

private extension DetermineStateSyncService {
    func performMainSyncUp() {
        mainSubscription?.unsubscribe()

        do {
            let connection = try chainRegistry.getConnectionOrError(for: chainId)
            let runtimeService = try chainRegistry.getRuntimeProviderOrError(for: chainId)

            mainSubscription = CallbackBatchStorageSubscription(
                requests: [
                    createCandidatesRequest(for: candidateAccountId),
                    createAccountToAliasRequest(for: mobRuleAccountId, mappingKey: .mobRuleAlias),
                    createAccountToAliasRequest(for: scoreAccountId, mappingKey: .scoreAlias),
                    createAccountToAliasRequest(for: resourcesAccountId, mappingKey: .resourcesAlias),
                    createMemberKeysRequest(for: memberKey),
                    createConsumerInfoRequest(for: walletAccountId)
                ],
                connection: connection,
                runtimeService: runtimeService,
                repository: nil,
                operationQueue: operationQueue,
                callbackQueue: proccessingQueue
            ) { [weak self] result in
                switch result {
                case let .success(model):
                    self?.logger.debug("Changes: \(model)")
                    self?.complete(nil)
                    self?.handleMainChange(model)
                case let .failure(error):
                    self?.logger.error("Subscription failed: \(error)")
                    self?.complete(error)
                }
            }

            mainSubscription?.subscribe()
        } catch {
            completeImmediate(error)
        }
    }

    func createCandidatesRequest(for accountId: AccountId) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: ProofOfInkPallet.candidatesPath,
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: accountId) }
            ),
            mappingKey: DetermineStateSync.MainChange.Key.candidate.rawValue
        )
    }

    func createAccountToAliasRequest(
        for accountId: AccountId,
        mappingKey: DetermineStateSync.MainChange.Key
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: PeoplePallet.accountToAliasPath,
                localKey: "",
                keyParamClosure: { accountId }
            ),
            mappingKey: mappingKey.rawValue
        )
    }

    func createMemberKeysRequest(
        for memberKey: BandersnatchPubKey
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: PeoplePallet.memberKeysPath,
                localKey: "",
                keyParamClosure: {
                    BytesCodable(wrappedValue: memberKey)
                }
            ),
            mappingKey: DetermineStateSync.MainChange.Key.keys.rawValue
        )
    }

    func createConsumerInfoRequest(
        for accountId: AccountId
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: ResourcesPallet.consumers,
                localKey: "",
                keyParamClosure: {
                    BytesCodable(wrappedValue: accountId)
                }
            ),
            mappingKey: DetermineStateSync.MainChange.Key.consumerInfo.rawValue
        )
    }

    func handleMainChange(_ change: DetermineStateSync.MainChange) {
        observers.forEach {
            ($0.target as? DetermineStateSyncServiceObserver)?
                .determineStateSyncChanged(by: change)
        }
        handlePersonIdChange(change.personId)
    }
}

// MARK: - Person record sync up

private extension DetermineStateSyncService {
    func handlePersonIdChange(
        _ change: UncertainStorage<PeoplePallet.PersonalId?>
    ) {
        let oldValue = personId

        if case let .defined(personId) = change, let personId {
            self.personId = personId
        } else {
            cancelPersonSubscription()
            personId = nil
        }

        if let personId, oldValue != personId {
            performPersonSyncUp(with: personId, memberKey: memberKey)
        }
    }

    func performPersonSyncUp(
        with personId: PeoplePallet.PersonalId,
        memberKey: BandersnatchPubKey
    ) {
        cancelPersonSubscription()

        do {
            let connection = try chainRegistry.getConnectionOrError(for: chainId)
            let runtimeService = try chainRegistry.getRuntimeProviderOrError(for: chainId)

            personSubscription = CallbackBatchStorageSubscription(
                requests: [
                    createPersonRecordRequest(with: personId),
                    createMemberRecordRequest(memberKey: memberKey),
                    createProofOfInkRequest(with: personId)
                ],
                connection: connection,
                runtimeService: runtimeService,
                repository: nil,
                operationQueue: operationQueue,
                callbackQueue: proccessingQueue
            ) { [weak self] result in
                switch result {
                case let .success(model):
                    self?.logger.debug("Changes: \(model)")
                    self?.observers.forEach {
                        ($0.target as? DetermineStateSyncServiceObserver)?
                            .determineStateSyncChanged(by: model)
                    }
                case let .failure(error):
                    self?.logger.error("Subscription failed: \(error)")
                }
            }

            personSubscription?.subscribe()
        } catch {
            completeImmediate(error)
        }
    }

    func createPersonRecordRequest(
        with personId: PeoplePallet.PersonalId
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: PeoplePallet.peoplePath,
                localKey: "",
                keyParamClosure: { StringCodable(wrappedValue: personId) }
            ),
            mappingKey: DetermineStateSync.PersonChange.Key.personRecord.rawValue
        )
    }

    func createMemberRecordRequest(
        memberKey: BandersnatchPubKey
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.members(),
                localKey: "",
                keyParamClosure: {
                    let collectionId = BytesCodable(wrappedValue: PeoplePallet.membersIdentifier)
                    let codableMemberKey = BytesCodable(wrappedValue: memberKey)

                    return (collectionId, codableMemberKey)
                }
            ),
            mappingKey: DetermineStateSync.PersonChange.Key.memberRingPosition.rawValue
        )
    }

    func createProofOfInkRequest(
        with personId: PeoplePallet.PersonalId
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: ProofOfInkPallet.peoplePath,
                localKey: "",
                keyParamClosure: { StringCodable(wrappedValue: personId) }
            ),
            mappingKey: DetermineStateSync.PersonChange.Key.proofOfInkPerson.rawValue
        )
    }

    func cancelPersonSubscription() {
        personSubscription?.unsubscribe()
        personSubscription = nil
    }
}
