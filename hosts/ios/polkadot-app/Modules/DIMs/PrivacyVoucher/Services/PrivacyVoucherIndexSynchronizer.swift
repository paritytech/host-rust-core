import Foundation
import Operation_iOS
import SubstrateSdk
import CommonService
import ChainRegistry

protocol PrivacyVoucherIndexSynchronizing: BaseObservableStateStore<
    PrivacyVoucherIndexSynchronizer.State
> {
    var type: PrivacyVoucherType { get }

    func synchronizeState()
}

final class PrivacyVoucherIndexSynchronizer: BaseObservableStateStore<
    PrivacyVoucherIndexSynchronizer.State
> {
    let type: PrivacyVoucherType

    private let connection: JSONRPCEngine
    private let runtimeProvider: RuntimeProviderProtocol
    private let operationFactory: PrivacyVoucherOperationMaking
    private let generator: PrivacyVoucherGenerating
    private let operationQueue: OperationQueue
    private let syncQueue: DispatchQueue

    private var cancellable: CancellableCallStore?

    init(
        type: PrivacyVoucherType,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol,
        operationFactory: PrivacyVoucherOperationMaking = PrivacyVoucherOperationFactory(),
        generator: PrivacyVoucherGenerating = PrivacyVoucherGenerator(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.type = type
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.operationFactory = operationFactory
        self.generator = generator
        self.operationQueue = operationQueue
        syncQueue = DispatchQueue(label: "PrivacyVoucherIndexSynchronizer.syncQueue")
        super.init(logger: logger)
    }
}

extension PrivacyVoucherIndexSynchronizer: PrivacyVoucherIndexSynchronizing {
    struct State: Equatable {
        let nextIndex: Int?
        let isSynchronizing: Bool
        let isCachedValue: Bool
    }

    func synchronizeState() {
        syncQueue.async { [weak self] in
            guard let self else {
                return
            }

            let currentState = stateObservable.state

            if currentState?.isSynchronizing == true {
                return
            }

            let cancellable = CancellableCallStore()

            stateObservable.state = .init(
                nextIndex: currentState?.nextIndex,
                isSynchronizing: true,
                isCachedValue: true
            )

            executeCancellable(
                wrapper: remoteNextIndex(),
                inOperationQueue: operationQueue,
                backingCallIn: cancellable,
                runningCallbackIn: syncQueue
            ) { [weak self] result in
                guard let self else {
                    return
                }

                switch result {
                case let .success(value):
                    stateObservable.state = .init(
                        nextIndex: value,
                        isSynchronizing: false,
                        isCachedValue: false
                    )
                case .failure:
                    stateObservable.state = .init(
                        nextIndex: currentState?.nextIndex,
                        isSynchronizing: false,
                        isCachedValue: true
                    )
                }
            }
        }
    }
}

private extension PrivacyVoucherIndexSynchronizer {
    static let syncUpVouchersBatchSize = 10

    func remoteNextIndex() -> CompoundOperationWrapper<Int> {
        let lastIndexWrapper = fetchLastExistingIndex()

        let finalizeOperation = ClosureOperation<Int> {
            let lastIndex = try lastIndexWrapper.targetOperation
                .extractNoCancellableResultData()
            return (lastIndex ?? -1) + 1
        }
        finalizeOperation.addDependency(lastIndexWrapper.targetOperation)

        return .init(
            targetOperation: finalizeOperation,
            dependencies: lastIndexWrapper.allOperations
        )
    }

    func fetchLastExistingIndex(
        startIndex: Int = 0,
        currentResult: Int? = nil
    ) -> CompoundOperationWrapper<Int?> {
        let deriveMemberKeysOperation = ClosureOperation<[Data]> { [generator, type] in
            let endIndex = startIndex + Self.syncUpVouchersBatchSize
            var result = [Data]()

            for index in startIndex ..< endIndex {
                try result.append(
                    generator.deriveKey(for: type, index: index).memberKey
                )
            }

            return result
        }

        let keysToRingWrapper = syncUpKeysToRing(
            deriveMemberKeysOperation: deriveMemberKeysOperation
        )

        let finalizeWrapper = finalizeSyncUp(
            startIndex: startIndex,
            currentResult: currentResult,
            deriveMemberKeysOperation: deriveMemberKeysOperation,
            keysToRingWrapper: keysToRingWrapper
        )

        return .init(
            targetOperation: finalizeWrapper.targetOperation,
            dependencies: finalizeWrapper.dependencies
                + keysToRingWrapper.allOperations
                + [deriveMemberKeysOperation]
        )
    }

    func syncUpKeysToRing(
        deriveMemberKeysOperation: ClosureOperation<[Data]>
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.KeysToRing?]> {
        let wrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.KeysToRing?]>

        wrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [operationFactory, connection, runtimeProvider] in
            let memberKeys = try deriveMemberKeysOperation
                .extractNoCancellableResultData()

            guard memberKeys.count == Self.syncUpVouchersBatchSize else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            return operationFactory.fetchKeysToRing(
                forVoucherKeys: memberKeys,
                connection: connection,
                runtimeProvider: runtimeProvider
            )
        }

        wrapper.addDependency(operations: [deriveMemberKeysOperation])

        return wrapper
    }

    func finalizeSyncUp(
        startIndex: Int,
        currentResult: Int?,
        deriveMemberKeysOperation: ClosureOperation<[Data]>,
        keysToRingWrapper: CompoundOperationWrapper<[PrivacyVoucherPallet.KeysToRing?]>
    ) -> CompoundOperationWrapper<Int?> {
        let wrapper: CompoundOperationWrapper<Int?>

        wrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            let memberKeys = try deriveMemberKeysOperation
                .extractNoCancellableResultData()

            let keysToRingList = try keysToRingWrapper.targetOperation
                .extractNoCancellableResultData()

            guard memberKeys.count == keysToRingList.count, let self else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            var newResult = currentResult

            for (index, value) in keysToRingList.enumerated() where value != nil {
                newResult = startIndex + index
            }

            if newResult != currentResult {
                return fetchLastExistingIndex(
                    startIndex: startIndex + Self.syncUpVouchersBatchSize,
                    currentResult: newResult
                )
            } else {
                return .createWithResult(newResult)
            }
        }

        wrapper.addDependency(wrapper: keysToRingWrapper)

        return wrapper
    }
}
