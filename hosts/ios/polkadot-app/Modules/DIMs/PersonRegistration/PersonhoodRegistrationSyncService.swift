import Foundation
import Operation_iOS
import SubstrateSdk
import CommonService
import SubstrateStorageSubscription
import Individuality
import KeyDerivation

protocol PersonhoodRegistrationSyncObserver: AnyObject {
    func personhoodRegistrationSyncChanged(by change: PersonhoodRegistrationSyncChange)
}

final class PersonhoodRegistrationSyncService: BaseSyncService {
    let candidateAccountId: AccountId
    let mobRuleAccountId: AccountId
    let scoreAccountId: AccountId
    let resourcesAccountId: AccountId
    let memberKey: BandersnatchPubKey
    let connection: JSONRPCEngine
    let runtimeService: RuntimeCodingServiceProtocol
    let proccessingQueue: DispatchQueue
    let operationQueue: OperationQueue
    let observers: [PersonhoodRegistrationSyncObserver]

    private var subscription: CallbackBatchStorageSubscription<PersonhoodRegistrationSyncChange>?

    private var personalId: PeoplePallet.PersonalId?
    private var ringIndex: MembersPallet.RingIndex?

    init(
        candidateAccountId: AccountId,
        mobRuleAccountId: AccountId,
        scoreAccountId: AccountId,
        resourcesAccountId: AccountId,
        memberKey: BandersnatchPubKey,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        observers: [PersonhoodRegistrationSyncObserver],
        operationQueue: OperationQueue,
        proccessingQueue: DispatchQueue,
        logger: LoggerProtocol
    ) {
        self.candidateAccountId = candidateAccountId
        self.mobRuleAccountId = mobRuleAccountId
        self.scoreAccountId = scoreAccountId
        self.resourcesAccountId = resourcesAccountId
        self.memberKey = memberKey
        self.connection = connection
        self.runtimeService = runtimeService
        self.observers = observers
        self.proccessingQueue = proccessingQueue
        self.operationQueue = operationQueue

        super.init(logger: logger)
    }

    private func createProofOfInkCandidatesRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: ProofOfInkPallet.candidatesPath,
                localKey: "",
                keyParamClosure: { [candidateAccountId] in BytesCodable(wrappedValue: candidateAccountId) }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.proofOfInkCandidate.rawValue
        )
    }

    private func createGameCandidatesRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: ScorePallet.participants,
                localKey: "",
                keyParamClosure: { [candidateAccountId] in
                    GamePallet.AccountOrPerson.account(accountID: candidateAccountId)
                }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.gameCandidate.rawValue
        )
    }

    private func createAccountToAliasRequest(
        with accountId: AccountId,
        mappingKey: PersonhoodRegistrationSyncChange.Key
    ) -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: PeoplePallet.accountToAliasPath,
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: accountId) }
            ),
            mappingKey: mappingKey.rawValue
        )
    }

    private func createMemberKeysRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: PeoplePallet.memberKeysPath,
                localKey: "",
                keyParamClosure: { [memberKey] in BytesCodable(wrappedValue: memberKey) }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.keys.rawValue
        )
    }

    private func createPersonRecordRequest() -> BatchStorageSubscriptionRequest? {
        guard let personalId else {
            return nil
        }
        return BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: PeoplePallet.peoplePath,
                localKey: "",
                keyParamClosure: { StringCodable(wrappedValue: personalId) }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.personRecord.rawValue
        )
    }

    private func createMemberRecordRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.members(),
                localKey: "",
                keyParamClosure: { [memberKey] in
                    let collectionId = BytesCodable(wrappedValue: PeoplePallet.membersIdentifier)

                    return (collectionId, BytesCodable(wrappedValue: memberKey))
                }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.memberRingPosition.rawValue
        )
    }

    private func createKeysStatusRequest() -> BatchStorageSubscriptionRequest? {
        guard let ringIndex else {
            return nil
        }

        return BatchStorageSubscriptionRequest(
            innerRequest: DoubleMapSubscriptionRequest(
                storagePath: MembersPallet.Storage.ringKeysStatus(),
                localKey: "",
                keyParamClosure: {
                    (
                        BytesCodable(wrappedValue: PeoplePallet.membersIdentifier),
                        StringCodable(wrappedValue: ringIndex)
                    )
                }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.keysStatus.rawValue
        )
    }

    private func createBestBlockTimestampRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: UnkeyedSubscriptionRequest(
                storagePath: TimestampPallet.timestampNowPath,
                localKey: ""
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.bestBlockTimestamp.rawValue
        )
    }

    private func createCollectionInfoRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: MembersPallet.Storage.collections(),
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: PeoplePallet.membersIdentifier) }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.collectionInfo.rawValue
        )
    }

    private func createRingsStateRequest() -> BatchStorageSubscriptionRequest {
        BatchStorageSubscriptionRequest(
            innerRequest: MapSubscriptionRequest(
                storagePath: MembersPallet.Storage.ringsState(),
                localKey: "",
                keyParamClosure: { BytesCodable(wrappedValue: PeoplePallet.membersIdentifier) }
            ),
            mappingKey: PersonhoodRegistrationSyncChange.Key.ringsState.rawValue
        )
    }

    private func notifyObservers(for change: PersonhoodRegistrationSyncChange) {
        observers.forEach { $0.personhoodRegistrationSyncChanged(by: change) }
    }

    private func updateSubscriptionRelatedData(from model: PersonhoodRegistrationSyncChange) {
        var shouldRestartSubscription = false

        if case let .defined(newPersonalId) = model.personalId,
           personalId != newPersonalId {
            personalId = newPersonalId
            shouldRestartSubscription = true
        }

        if case let .defined(memberRingPosition) = model.memberRingPosition,
           ringIndex != memberRingPosition?.ringIndex {
            ringIndex = memberRingPosition?.ringIndex
            shouldRestartSubscription = true
        }

        if shouldRestartSubscription, subscription != nil {
            proccessingQueue.async { [weak self] in
                self?.performSyncUp()
            }
        }
    }

    override func performSyncUp() {
        subscription?.unsubscribe()

        subscription = CallbackBatchStorageSubscription(
            requests: [
                createProofOfInkCandidatesRequest(),
                createGameCandidatesRequest(),
                createAccountToAliasRequest(with: mobRuleAccountId, mappingKey: .mobRuleAlias),
                createAccountToAliasRequest(with: scoreAccountId, mappingKey: .scoreAlias),
                createAccountToAliasRequest(with: resourcesAccountId, mappingKey: .resourcesAlias),
                createMemberKeysRequest(),
                createPersonRecordRequest(),
                createMemberRecordRequest(),
                createKeysStatusRequest(),
                createBestBlockTimestampRequest(),
                createCollectionInfoRequest(),
                createRingsStateRequest()
            ].compactMap { $0 },
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
                self?.notifyObservers(for: model)
                self?.updateSubscriptionRelatedData(from: model)
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
