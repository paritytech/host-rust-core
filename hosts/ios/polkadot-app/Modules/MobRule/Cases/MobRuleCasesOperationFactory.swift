import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import Individuality
import ChainRegistry

protocol MobRuleCasesOperationFactoryProtocol {
    func fetchCasesInfo(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        aliasAccountId: AccountId
    ) -> CompoundOperationWrapper<MobRuleCasesInfo>
}

enum MobRuleCasesOperationFactoryError: Error {
    case missingAlias
}

struct MobRuleCasesInfo {
    let openCases: MobRulePallet.OpenCasesResult
    let allCases: [MobRulePallet.CaseIndex: MobRuleCaseData]
    let userVotes: MobRulePallet.UserVotesResult
}

final class MobRuleCasesOperationFactory: MobRuleCasesOperationFactoryProtocol {
    let operationQueue: OperationQueue

    let requestFactory: StorageRequestFactoryProtocol

    init(operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue) {
        self.operationQueue = operationQueue

        requestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }

    func fetchCasesInfo(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        aliasAccountId: AccountId
    ) -> CompoundOperationWrapper<MobRuleCasesInfo> {
        let fetchAliasWrapper = fetchAliasWrapper(
            for: aliasAccountId,
            connection: connection,
            runtimeProvider: runtimeProvider
        )

        let fetchOpenCasesWrapper = fetchOpenCasesWrapper(for: connection, runtimeProvider: runtimeProvider)
        let fetchRipeCasesWrapper = fetchRipeCasesWrapper(for: connection, runtimeProvider: runtimeProvider)
        let fetchDoneCasesWrapper = fetchDoneCasesWrapper(for: connection, runtimeProvider: runtimeProvider)

        let fetchVotesWrapper = fetchUserVotesWrapper(
            for: connection,
            runtimeProvider: runtimeProvider,
            aliasClosure: {
                guard let contexualAlias = try fetchAliasWrapper.targetOperation.extractNoCancellableResultData() else {
                    throw MobRuleCasesOperationFactoryError.missingAlias
                }
                return contexualAlias.alias
            }
        )

        fetchVotesWrapper.addDependency(wrapper: fetchAliasWrapper)

        let mergeOperation = ClosureOperation<MobRuleCasesInfo> { [weak self] in
            guard let self else {
                throw BaseOperationError.unexpectedDependentResult
            }

            let openCases = try fetchOpenCasesWrapper.targetOperation.extractNoCancellableResultData()
            let ripeCases = try fetchRipeCasesWrapper.targetOperation.extractNoCancellableResultData()
            let doneCases = try fetchDoneCasesWrapper.targetOperation.extractNoCancellableResultData()
            let votes = try fetchVotesWrapper.targetOperation.extractNoCancellableResultData()

            return .init(
                openCases: openCases,
                allCases: makeAllCases(
                    open: openCases,
                    ripe: ripeCases,
                    done: doneCases
                ),
                userVotes: votes
            )
        }

        mergeOperation.addDependency(fetchOpenCasesWrapper.targetOperation)
        mergeOperation.addDependency(fetchRipeCasesWrapper.targetOperation)
        mergeOperation.addDependency(fetchDoneCasesWrapper.targetOperation)
        mergeOperation.addDependency(fetchVotesWrapper.targetOperation)

        return CompoundOperationWrapper(
            targetOperation: mergeOperation,
            dependencies: fetchAliasWrapper.allOperations
                + fetchOpenCasesWrapper.allOperations
                + fetchRipeCasesWrapper.allOperations
                + fetchDoneCasesWrapper.allOperations
                + fetchVotesWrapper.allOperations
        )
    }
}

private extension MobRuleCasesOperationFactory {
    func fetchAliasWrapper(
        for aliasAccountId: AccountId,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<PeoplePallet.RevisedContextualAlias?> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchAliasWrapper: CompoundOperationWrapper<[StorageResponse<PeoplePallet.RevisedContextualAlias>]>

        fetchAliasWrapper = requestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: aliasAccountId)] },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PeoplePallet.accountToAliasPath
        )

        fetchAliasWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<PeoplePallet.RevisedContextualAlias?> {
            try fetchAliasWrapper.targetOperation.extractNoCancellableResultData().first?.value
        }

        mappingOperation.addDependency(fetchAliasWrapper.targetOperation)

        return fetchAliasWrapper
            .insertingTail(operation: mappingOperation)
            .insertingHead(operations: [codingFactoryOperation])
    }

    func fetchOpenCasesWrapper(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<MobRulePallet.OpenCasesResult> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let casesFetchWrapper: CompoundOperationWrapper<MobRulePallet.OpenCasesKeyResult>

        casesFetchWrapper = requestFactory.queryByPrefix(
            engine: connection,
            request: UnkeyedRemoteStorageRequest(storagePath: MobRulePallet.openCasesPath),
            storagePath: MobRulePallet.openCasesPath,
            factory: { try codingFactoryOperation.extractNoCancellableResultData() }
        )
        casesFetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mapOperation = ClosureOperation<MobRulePallet.OpenCasesResult> {
            let items = try casesFetchWrapper.targetOperation.extractNoCancellableResultData()

            return items.reduce(into: MobRulePallet.OpenCasesResult()) { accum, pair in
                accum[pair.key.index] = pair.value
            }
        }

        mapOperation.addDependency(casesFetchWrapper.targetOperation)

        return casesFetchWrapper
            .insertingHead(operations: [codingFactoryOperation])
            .insertingTail(operation: mapOperation)
    }

    func fetchRipeCasesWrapper(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<MobRulePallet.RipeCasesResult> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let casesFetchWrapper: CompoundOperationWrapper<MobRulePallet.RipeCasesKeyResult>

        casesFetchWrapper = requestFactory.queryByPrefix(
            engine: connection,
            request: UnkeyedRemoteStorageRequest(storagePath: MobRulePallet.ripeCasesPath),
            storagePath: MobRulePallet.ripeCasesPath,
            factory: { try codingFactoryOperation.extractNoCancellableResultData() }
        )
        casesFetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mapOperation = ClosureOperation<MobRulePallet.RipeCasesResult> {
            let items = try casesFetchWrapper.targetOperation.extractNoCancellableResultData()

            return items.reduce(into: MobRulePallet.RipeCasesResult()) { accum, pair in
                accum[pair.key.index] = pair.value
            }
        }

        mapOperation.addDependency(casesFetchWrapper.targetOperation)

        return casesFetchWrapper
            .insertingHead(operations: [codingFactoryOperation])
            .insertingTail(operation: mapOperation)
    }

    func fetchDoneCasesWrapper(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<MobRulePallet.DoneCasesResult> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let casesFetchWrapper: CompoundOperationWrapper<MobRulePallet.DoneCasesKeyResult>

        casesFetchWrapper = requestFactory.queryByPrefix(
            engine: connection,
            request: UnkeyedRemoteStorageRequest(storagePath: MobRulePallet.doneCasesPath),
            storagePath: MobRulePallet.doneCasesPath,
            factory: { try codingFactoryOperation.extractNoCancellableResultData() }
        )
        casesFetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mapOperation = ClosureOperation<MobRulePallet.DoneCasesResult> {
            let items = try casesFetchWrapper.targetOperation.extractNoCancellableResultData()

            return items.reduce(into: MobRulePallet.DoneCasesResult()) { accum, pair in
                accum[pair.key.index] = pair.value
            }
        }

        mapOperation.addDependency(casesFetchWrapper.targetOperation)

        return casesFetchWrapper
            .insertingHead(operations: [codingFactoryOperation])
            .insertingTail(operation: mapOperation)
    }

    func fetchUserVotesWrapper(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        aliasClosure: @escaping () throws -> PeoplePallet.Alias
    ) -> CompoundOperationWrapper<MobRulePallet.UserVotesResult> {
        let keysQueryFactory = StorageKeysOperationFactory(operationQueue: operationQueue)
        let fetchWrapper: CompoundOperationWrapper<[MobRulePallet.ExistingVoteKey]>

        fetchWrapper = keysQueryFactory.createKeysFetchWrapper(
            by: MobRulePallet.votesPath,
            runtimeService: runtimeProvider,
            connection: connection
        )

        let mapOperation = ClosureOperation<MobRulePallet.UserVotesResult> {
            let items = try fetchWrapper.targetOperation.extractNoCancellableResultData()
            let alias = try aliasClosure()

            return items.reduce(into: MobRulePallet.UserVotesResult()) { result, item in
                if item.alias == alias {
                    result.insert(item.caseIndex)
                }
            }
        }

        mapOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper.insertingTail(operation: mapOperation)
    }

    func makeAllCases(
        open: MobRulePallet.OpenCasesResult,
        ripe: MobRulePallet.RipeCasesResult,
        done: MobRulePallet.DoneCasesResult
    ) -> [MobRulePallet.CaseIndex: MobRuleCaseData] {
        var result = [MobRulePallet.CaseIndex: MobRuleCaseData]()

        for (index, item) in open {
            result[index] = .open(item)
        }

        for (index, item) in ripe {
            result[index] = .ripe(item)
        }

        for (index, item) in done {
            result[index] = .done(item)
        }

        return result
    }
}
