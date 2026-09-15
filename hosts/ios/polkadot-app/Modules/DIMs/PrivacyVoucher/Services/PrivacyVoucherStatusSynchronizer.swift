import Foundation
import SubstrateSdk
import Operation_iOS
import CommonService
import ChainRegistry

protocol PrivacyVoucherStatusSynchronizing: BaseObservableStateStore<
    PrivacyVoucherStatusSynchronizer.State
> {
    func synchronizeState()
    func markAsClaimed(with result: ClaimRewardsResult)
}

final class PrivacyVoucherStatusSynchronizer: BaseObservableStateStore<
    PrivacyVoucherStatusSynchronizer.State
> {
    private let connection: JSONRPCEngine
    private let runtimeProvider: RuntimeProviderProtocol
    private let operationFactory: PrivacyVoucherOperationMaking
    private let dataProviderFactory: PrivacyVoucherDataProviderMaking
    private let repositoryFactory: PrivacyVoucherRepositoryMaking
    private let operationQueue: OperationQueue

    private let syncQueue = DispatchQueue(label: "PrivacyVoucherStatusSynchronizer.syncQueue")
    private let cancellableStore = CancellableCallStore()

    private var localVoucherProvider: StreamableProvider<LocalPrivacyVoucher>?
    private var localVouchersByIdentifiers = [String: LocalPrivacyVoucher]()

    init(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        operationFactory: PrivacyVoucherOperationMaking = PrivacyVoucherOperationFactory(),
        dataProviderFactory: PrivacyVoucherDataProviderMaking = PrivacyVoucherDataProviderFactory(),
        repositoryFactory: PrivacyVoucherRepositoryMaking = PrivacyVoucherRepositoryFactory(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.operationFactory = operationFactory
        self.dataProviderFactory = dataProviderFactory
        self.repositoryFactory = repositoryFactory
        self.operationQueue = operationQueue
        super.init(logger: logger)
        subscribeLocalVouchers()
    }
}

extension PrivacyVoucherStatusSynchronizer: PrivacyVoucherStatusSynchronizing {
    typealias State = [PrivacyVoucherStatus: [RemotePrivacyVoucher]]

    func synchronizeState() {
        syncQueue.async { [weak self] in
            self?.performSynchronizeState()
        }
    }

    func markAsClaimed(with result: ClaimRewardsResult) {
        syncQueue.async { [weak self] in
            self?.performMarkAsClaimed(
                with: result
            )
        }
    }
}

extension PrivacyVoucherStatusSynchronizer: LocalStorageProviderObserving {
    func subscribeLocalVouchers() {
        let provider = dataProviderFactory.createLocalVoucherProvider()
        localVoucherProvider = provider

        addStreamableProviderObserver(
            for: provider,
            updateClosure: { [weak self] changes in
                guard let self else {
                    return
                }
                localVouchersByIdentifiers = changes.mergeToDict(localVouchersByIdentifiers)
                synchronizeState()
            },
            failureClosure: { [weak self] error in
                self?.logger.error("Did receive error: \(error)")
            },
            callbackQueue: syncQueue,
            options: .allNonblocking()
        )
    }
}

private extension PrivacyVoucherStatusSynchronizer {
    func performSynchronizeState() {
        if cancellableStore.hasCall {
            cancellableStore.cancel()
        }

        executeCancellable(
            wrapper: syncUpWrapper(),
            inOperationQueue: operationQueue,
            backingCallIn: cancellableStore,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            switch result {
            case let .success(value):
                self?.logger.debug("State synchronization finished")
                self?.stateObservable.state = value
            case let .failure(error):
                self?.logger.error("State synchronization error: \(error)")
            }
        }
    }

    class SyncUpOperationState {
        var localVouchersToCheck = [LocalPrivacyVoucher]()
        var keysToRingToCheck = [PrivacyVoucherPallet.KeysToRing]()

        var usedVouchers = [RemotePrivacyVoucher]()
        var claimableVouchers = [RemotePrivacyVoucher]()
        var buildingVouchers = [RemotePrivacyVoucher]()
    }

    func syncUpWrapper() -> CompoundOperationWrapper<State> {
        let state = SyncUpOperationState()

        let localVouchers = Array(localVouchersByIdentifiers.values)

        let keysToRingWrapper = keysToRingWrapper(
            localVouchers: localVouchers
        )

        let usedTicketsWrapper = usedTicketsWrapper(
            localVouchers: localVouchers,
            keysToRingWrapper: keysToRingWrapper,
            state: state
        )

        let claimableRingsWrapper = claimableRingsWrapper(
            usedTicketsWrapper: usedTicketsWrapper,
            state: state
        )

        let buildingRingsWrapper = buildingRingsWrapper(
            claimableRingsWrapper: claimableRingsWrapper,
            state: state
        )

        let finalizeOperation = finalizeSyncOperation(
            buildingRingsWrapper: buildingRingsWrapper,
            state: state
        )

        return .init(
            targetOperation: finalizeOperation,
            dependencies: keysToRingWrapper.allOperations
                + usedTicketsWrapper.allOperations
                + claimableRingsWrapper.allOperations
                + buildingRingsWrapper.allOperations
        )
    }

    func keysToRingWrapper(
        localVouchers: [LocalPrivacyVoucher]
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.KeysToRing?]> {
        if localVouchers.isEmpty {
            .createWithResult([])
        } else {
            operationFactory.fetchKeysToRing(
                forVoucherKeys: localVouchers.map(\.key.memberKey),
                connection: connection,
                runtimeProvider: runtimeProvider
            )
        }
    }

    func usedTicketsWrapper(
        localVouchers: [LocalPrivacyVoucher],
        keysToRingWrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.KeysToRing?]>,
        state: SyncUpOperationState
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.UsedTicket?]> {
        let wrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.UsedTicket?]>

        wrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            var aliasesToCheck = [Data]()

            state.localVouchersToCheck.reserveCapacity(localVouchers.count)
            state.keysToRingToCheck.reserveCapacity(localVouchers.count)
            aliasesToCheck.reserveCapacity(localVouchers.count)

            let optionalKeysToRingList = try keysToRingWrapper.targetOperation.extractNoCancellableResultData()

            guard localVouchers.count == optionalKeysToRingList.count else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            state.keysToRingToCheck = optionalKeysToRingList.enumerated().compactMap { index, value in
                if let value {
                    let voucher = localVouchers[index]
                    state.localVouchersToCheck.append(voucher)
                    aliasesToCheck.append(voucher.alias)
                    return value
                } else {
                    return nil
                }
            }

            if state.keysToRingToCheck.isEmpty {
                return .createWithResult([])
            } else {
                return operationFactory.fetchUsedTickets(
                    for: state.keysToRingToCheck,
                    aliases: aliasesToCheck,
                    connection: connection,
                    runtimeProvider: runtimeProvider
                )
            }
        }

        wrapper.addDependency(wrapper: keysToRingWrapper)

        return wrapper
    }

    func claimableRingsWrapper(
        usedTicketsWrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.UsedTicket?]>,
        state: SyncUpOperationState
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.ClaimableRing?]> {
        let wrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.ClaimableRing?]>

        wrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            let optionalUsedTickets = try usedTicketsWrapper.targetOperation.extractNoCancellableResultData()

            guard state.localVouchersToCheck.count == optionalUsedTickets.count else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            let oldVouchersToCheck = state.localVouchersToCheck
            let oldKeysToRing = state.keysToRingToCheck

            state.localVouchersToCheck.removeAll(keepingCapacity: true)
            state.keysToRingToCheck.removeAll(keepingCapacity: true)

            optionalUsedTickets.enumerated().forEach { index, value in
                if value != nil || oldVouchersToCheck[index].isClaimed {
                    state.usedVouchers.append(RemotePrivacyVoucher(
                        localData: oldVouchersToCheck[index],
                        status: .used,
                        balanceOf: oldKeysToRing[index].balanceOf,
                        ringIndex: oldKeysToRing[index].ringIndex
                    ))
                } else {
                    state.localVouchersToCheck.append(oldVouchersToCheck[index])
                    state.keysToRingToCheck.append(oldKeysToRing[index])
                }
            }

            if state.keysToRingToCheck.isEmpty {
                return .createWithResult([])
            } else {
                return operationFactory.fetchClaimableRings(
                    for: state.keysToRingToCheck,
                    connection: connection,
                    runtimeProvider: runtimeProvider
                )
            }
        }

        wrapper.addDependency(wrapper: usedTicketsWrapper)

        return wrapper
    }

    func buildingRingsWrapper(
        claimableRingsWrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.ClaimableRing?]>,
        state: SyncUpOperationState
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.BuildingRing?]> {
        let wrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.BuildingRing?]>

        wrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            let optionalClaimableRings = try claimableRingsWrapper.targetOperation.extractNoCancellableResultData()

            guard state.localVouchersToCheck.count == optionalClaimableRings.count else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            let oldVouchersToCheck = state.localVouchersToCheck
            let oldKeysToRing = state.keysToRingToCheck

            state.localVouchersToCheck.removeAll(keepingCapacity: true)
            state.keysToRingToCheck.removeAll(keepingCapacity: true)

            optionalClaimableRings.enumerated().forEach { index, value in
                if value != nil {
                    state.claimableVouchers.append(RemotePrivacyVoucher(
                        localData: oldVouchersToCheck[index],
                        status: .claimable,
                        balanceOf: oldKeysToRing[index].balanceOf,
                        ringIndex: oldKeysToRing[index].ringIndex
                    ))
                } else {
                    state.localVouchersToCheck.append(oldVouchersToCheck[index])
                    state.keysToRingToCheck.append(oldKeysToRing[index])
                }
            }

            if state.keysToRingToCheck.isEmpty {
                return .createWithResult([])
            } else {
                return operationFactory.fetchBuildingRings(
                    for: state.keysToRingToCheck.map(\.balanceOf),
                    connection: connection,
                    runtimeProvider: runtimeProvider
                )
            }
        }

        wrapper.addDependency(wrapper: claimableRingsWrapper)

        return wrapper
    }

    func finalizeSyncOperation(
        buildingRingsWrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.BuildingRing?]>,
        state: SyncUpOperationState
    ) -> ClosureOperation<State> {
        let operation = ClosureOperation<State> {
            let optionalBuildingRings = try buildingRingsWrapper.targetOperation.extractNoCancellableResultData()

            guard state.localVouchersToCheck.count == optionalBuildingRings.count else {
                throw BaseOperationError.unexpectedDependentResult
            }

            optionalBuildingRings.enumerated().forEach { index, value in
                if value != nil {
                    state.buildingVouchers.append(RemotePrivacyVoucher(
                        localData: state.localVouchersToCheck[index],
                        status: .building,
                        balanceOf: state.keysToRingToCheck[index].balanceOf,
                        ringIndex: state.keysToRingToCheck[index].ringIndex
                    ))
                }
            }

            return [
                .used: state.usedVouchers,
                .claimable: state.claimableVouchers,
                .building: state.buildingVouchers
            ]
        }

        operation.addDependency(buildingRingsWrapper.targetOperation)

        return operation
    }

    func performMarkAsClaimed(
        with result: ClaimRewardsResult
    ) {
        execute(
            wrapper: markAsClaimedWrapper(
                with: result,
                currentState: stateObservable.state
            ),
            inOperationQueue: operationQueue,
            runningCallbackIn: syncQueue
        ) { [weak self] result in
            switch result {
            case let .success(value):
                self?.logger.debug("Update after claim finished")
                self?.stateObservable.state = value
            case let .failure(error):
                self?.logger.error("Update after claim error: \(error.localizedDescription)")
            }
        }
    }

    func markAsClaimedWrapper(
        with result: ClaimRewardsResult,
        currentState: State?
    ) -> CompoundOperationWrapper<State> {
        let updateStateOperation = updateStateOperation(
            with: result,
            currentState: currentState
        )

        let saveClaimedLocalVouchersWrapper = saveClaimedLocalVouchersWrapper(
            updateStateOperation: updateStateOperation
        )

        return saveClaimedLocalVouchersWrapper
            .insertingHead(operations: [updateStateOperation])
    }

    func updateStateOperation(
        with result: ClaimRewardsResult,
        currentState: State?
    ) -> BaseOperation<State> {
        ClosureOperation {
            var used = (currentState?[.used] ?? []).compactMap {
                let notPresentedInClaimed = result.claimedVouchersByIdentifier[$0.localData.identifier] == nil
                return notPresentedInClaimed ? $0 : nil
            }
            used.append(contentsOf: result.claimedVouchersByIdentifier.values.map {
                $0.markedAsClaimed()
            })

            let claimable = (currentState?[.claimable] ?? []).compactMap {
                let notPresentedInClaimed = result.claimedVouchersByIdentifier[$0.localData.identifier] == nil
                return notPresentedInClaimed ? $0 : nil
            }

            let building = currentState?[.building] ?? []

            return [
                .used: used,
                .claimable: claimable,
                .building: building
            ]
        }
    }

    func saveClaimedLocalVouchersWrapper(
        updateStateOperation: BaseOperation<State>
    ) -> CompoundOperationWrapper<State> {
        let repository = repositoryFactory.createLocalVoucherRepository(forFilter: nil)

        let saveOperation = repository.saveOperation({
            let state = try updateStateOperation.extractNoCancellableResultData()
            return (state[.used] ?? []).map(\.localData)
        }, { [] })
        saveOperation.addDependency(updateStateOperation)

        let resultOperation = ClosureOperation {
            try updateStateOperation.extractNoCancellableResultData()
        }
        resultOperation.addDependency(saveOperation)

        return .init(
            targetOperation: resultOperation,
            dependencies: [saveOperation]
        )
    }
}
