import Foundation
import SubstrateSdk
import Operation_iOS
import SubstrateStorageQuery
import KeyDerivation
import Individuality
import ChainRegistry

protocol PersonRegistrationQueryFactoryProtocol {
    func querySyncState(
        input: PersonRegistrationSyncInput,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<PersonRegistrationSyncState?>
}

struct PersonRegistrationSyncInput {
    let mobRuleAccountId: AccountId
    let scoreAccountId: AccountId
    let resourcesAccountId: AccountId
    let memberKey: BandersnatchPubKey
}

final class PersonRegistrationQueryFactory {
    private let storageRequestFactory: StorageRequestFactoryProtocol
    private let stateFactory: PersonRegistrationStateFactoryProtocol
    private let operationQueue: OperationQueue

    init(operationQueue: OperationQueue) {
        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
        stateFactory = PersonRegistrationStateFactory()
        self.operationQueue = operationQueue
    }
}

extension PersonRegistrationQueryFactory: PersonRegistrationQueryFactoryProtocol {
    func querySyncState(
        input: PersonRegistrationSyncInput,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<PersonRegistrationSyncState?> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let mobRuleAliasWrapper = aliasWrapper(
            for: input.mobRuleAccountId,
            connection: connection,
            dependingOn: codingFactoryOperation
        )
        let scoreAliasWrapper = aliasWrapper(
            for: input.scoreAccountId,
            connection: connection,
            dependingOn: codingFactoryOperation
        )
        let resourcesAliasWrapper = aliasWrapper(
            for: input.resourcesAccountId,
            connection: connection,
            dependingOn: codingFactoryOperation
        )

        let personIdWrapper: CompoundOperationWrapper<[StorageResponse<StringScaleMapper<PeoplePallet.PersonalId>>]>
        personIdWrapper = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: input.memberKey)] },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PeoplePallet.memberKeysPath
        )

        personIdWrapper.addDependency(operations: [codingFactoryOperation])

        let ringPositionWrapper: CompoundOperationWrapper<[StorageResponse<MembersPallet.RingPosition>]>
        ringPositionWrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) {
            self.storageRequestFactory.queryItems(
                engine: connection,
                keyParams1: { [BytesCodable(wrappedValue: PeoplePallet.membersIdentifier)] },
                keyParams2: { [BytesCodable(wrappedValue: input.memberKey)] },
                factory: { try codingFactoryOperation.extractNoCancellableResultData() },
                storagePath: MembersPallet.Storage.members()
            )
        }

        let ringKeysMetaWrapper: CompoundOperationWrapper<[StorageResponse<MembersPallet.RingKeysStatus>]>
        ringKeysMetaWrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) {
            if
                let record = try ringPositionWrapper.targetOperation.extractNoCancellableResultData().first?.value,
                let ringIndex = record.ringIndex {
                self.storageRequestFactory.queryItems(
                    engine: connection,
                    keyParams1: { [BytesCodable(wrappedValue: PeoplePallet.membersIdentifier)] },
                    keyParams2: { [StringCodable(wrappedValue: ringIndex)] },
                    factory: { try codingFactoryOperation.extractNoCancellableResultData() },
                    storagePath: MembersPallet.Storage.ringKeysStatus()
                )
            } else {
                .createWithResult([])
            }
        }

        ringKeysMetaWrapper.addDependency(wrapper: ringPositionWrapper)

        let ringKeysPageSizeOperation = StorageConstantOperation<MembersPallet.RingExponent>.operation(
            path: MembersPallet.Constants.maxFlexibleRingExponent(),
            dependingOn: codingFactoryOperation
        )

        ringKeysPageSizeOperation.addDependency(codingFactoryOperation)

        let finalMappingOperation = ClosureOperation<PersonRegistrationSyncState?> { [stateFactory] in
            let mobRuleAliasResponses = try mobRuleAliasWrapper.targetOperation.extractNoCancellableResultData()
            let scoreAliasResponses = try scoreAliasWrapper.targetOperation.extractNoCancellableResultData()
            let resourcesAliasResponses = try resourcesAliasWrapper.targetOperation.extractNoCancellableResultData()
            let personIdResponses = try personIdWrapper.targetOperation.extractNoCancellableResultData()
            let ringPositionResponses = try ringPositionWrapper.targetOperation.extractNoCancellableResultData()
            let ringKeysMetaResponses = try ringKeysMetaWrapper.targetOperation.extractNoCancellableResultData()
            let ringExponent = try ringKeysPageSizeOperation.extractNoCancellableResultData()

            let remoteState = PersonhoodRegistrationSyncState(
                personalId: personIdResponses.first?.value?.value,
                mobRuleAlias: mobRuleAliasResponses.first?.value,
                scoreAlias: scoreAliasResponses.first?.value,
                resourcesAlias: resourcesAliasResponses.first?.value,
                memberRingPosition: ringPositionResponses.first?.value
            )

            return stateFactory.makeState(
                remoteState: remoteState,
                memberRingPosition: ringPositionResponses.first?.value,
                keysStatus: ringKeysMetaResponses.first?.value,
                keysPerPage: ringExponent.ringCapacity
            )
        }

        finalMappingOperation.addDependency(mobRuleAliasWrapper.targetOperation)
        finalMappingOperation.addDependency(scoreAliasWrapper.targetOperation)
        finalMappingOperation.addDependency(resourcesAliasWrapper.targetOperation)
        finalMappingOperation.addDependency(personIdWrapper.targetOperation)
        finalMappingOperation.addDependency(ringPositionWrapper.targetOperation)
        finalMappingOperation.addDependency(ringKeysMetaWrapper.targetOperation)
        finalMappingOperation.addDependency(ringKeysPageSizeOperation)

        let wrapperDependencies = mobRuleAliasWrapper.allOperations
            + scoreAliasWrapper.allOperations
            + resourcesAliasWrapper.allOperations
            + personIdWrapper.allOperations
            + ringPositionWrapper.allOperations
            + ringKeysMetaWrapper.allOperations

        return CompoundOperationWrapper(
            targetOperation: finalMappingOperation,
            dependencies: [codingFactoryOperation, ringKeysPageSizeOperation] + wrapperDependencies
        )
    }
}

private extension PersonRegistrationQueryFactory {
    func aliasWrapper(
        for accountId: AccountId,
        connection: JSONRPCEngine,
        dependingOn codingFactoryOperation: BaseOperation<RuntimeCoderFactoryProtocol>
    ) -> CompoundOperationWrapper<[StorageResponse<PeoplePallet.RevisedContextualAlias>]> {
        let wrapper: CompoundOperationWrapper<[StorageResponse<PeoplePallet.RevisedContextualAlias>]>
        wrapper = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: accountId)] },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PeoplePallet.accountToAliasPath
        )

        wrapper.addDependency(operations: [codingFactoryOperation])

        return wrapper
    }
}
