import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService

protocol PrivacyVoucherStoreManaging: AnyObject {
    func synchronizeToRemoteNextIndex()

    func registerPrivacyVouchers(
        withCount count: Int,
        registerWrapperFactory: @escaping PrivacyVoucherStoreManager.RegisterFactory
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>
}

final class PrivacyVoucherStoreManager {
    private let type: PrivacyVoucherType
    private let indexSynchronizer: PrivacyVoucherIndexSynchronizing
    private let repositoryFactory: PrivacyVoucherRepositoryMaking
    private let generator: PrivacyVoucherGenerating
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    private let indexObserverQueue = DispatchQueue(label: "PrivacyVoucherStoreManager.indexObserverQueue")
    private weak var activeWrapper: CompoundOperationWrapper<ExtrinsicMonitorSubmission>?

    init(
        indexSynchronizer: PrivacyVoucherIndexSynchronizing,
        repositoryFactory: PrivacyVoucherRepositoryMaking = PrivacyVoucherRepositoryFactory(),
        generator: PrivacyVoucherGenerating = PrivacyVoucherGenerator(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        type = indexSynchronizer.type
        self.indexSynchronizer = indexSynchronizer
        self.repositoryFactory = repositoryFactory
        self.generator = generator
        self.operationQueue = operationQueue
        self.logger = logger
        addRemoteNextIndexObserver()
    }

    deinit {
        removeRemoteNextIndexObserver()
    }
}

extension PrivacyVoucherStoreManager: PrivacyVoucherStoreManaging {
    typealias RegisterFactory = ([LocalPrivacyVoucher]) throws
        -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>

    func registerPrivacyVouchers(
        withCount count: Int,
        registerWrapperFactory: @escaping RegisterFactory
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        let indexObserver = IndexForRegisterObserver(storeManager: self)

        let nextIndexOperation = AsyncClosureOperation<Int>(operationClosure: { completion in
            indexObserver.addObserver(with: completion)
        }, cancelationClosure: {
            indexObserver.removeObserver()
        })

        let generateOperation = ClosureOperation<[LocalPrivacyVoucher]> { [generator, type] in
            let startIndex = try nextIndexOperation.extractNoCancellableResultData()
            let endIndex = startIndex + count
            var result = [LocalPrivacyVoucher]()

            for index in startIndex ..< endIndex {
                try result.append(generator.generateLocalVoucher(with: type, index: index))
            }

            return result
        }
        generateOperation.addDependency(nextIndexOperation)

        let registerWrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) {
            let vouchers = try generateOperation.extractNoCancellableResultData()
            return try registerWrapperFactory(vouchers)
        }
        registerWrapper.addDependency(operations: [generateOperation])

        let saveVouchersWrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [repositoryFactory] in
            let extrinsicResult = try registerWrapper.targetOperation.extractNoCancellableResultData()

            switch extrinsicResult.status {
            case .success:
                let vouchers = try generateOperation.extractNoCancellableResultData()
                let repository = repositoryFactory.createLocalVoucherRepository(forFilter: nil)
                return .init(targetOperation: repository.saveOperation({ vouchers }, { [] }))
            case .failure:
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }
        }
        saveVouchersWrapper.addDependency(wrapper: registerWrapper)

        let finalizeOperation = ClosureOperation { [weak self] in
            let result = try registerWrapper.targetOperation
                .extractNoCancellableResultData()
            self?.synchronizeToRemoteNextIndex()
            return result
        }
        finalizeOperation.addDependency(saveVouchersWrapper.targetOperation)

        let newActiveWrapper = CompoundOperationWrapper(
            targetOperation: finalizeOperation,
            dependencies: [nextIndexOperation, generateOperation]
                + saveVouchersWrapper.allOperations
                + registerWrapper.allOperations
        )

        if let activeWrapper {
            newActiveWrapper.addDependency(wrapper: activeWrapper)
        }

        activeWrapper = newActiveWrapper

        // TODO: consider executing wrapper immediately and putting it into cancellable store
        return newActiveWrapper
    }

    func synchronizeToRemoteNextIndex() {
        indexSynchronizer.synchronizeState()
    }
}

private extension PrivacyVoucherStoreManager {
    final class IndexForRegisterObserver {
        private weak var storeManager: PrivacyVoucherStoreManager?

        private var isFinished = false

        init(storeManager: PrivacyVoucherStoreManager) {
            self.storeManager = storeManager
        }

        func addObserver(with completion: @escaping (Result<Int, Error>) -> Void) {
            guard let storeManager else {
                return
            }

            storeManager.indexSynchronizer.add(
                observer: self,
                queue: storeManager.indexObserverQueue
            ) { [weak self] _, state in
                guard let self, !isFinished else {
                    return
                }

                if state?.isSynchronizing == true {
                    return
                }

                isFinished = true
                removeObserver()

                if let nextIndex = state?.nextIndex,
                   state?.isCachedValue == false {
                    completion(.success(nextIndex))
                    return
                }

                fetchLocalNextIndex { result in
                    switch result {
                    case let .success(localValue):
                        completion(.success(max(localValue, state?.nextIndex ?? 0)))
                    case let .failure(error):
                        completion(.failure(error))
                    }
                }
            }
        }

        func removeObserver() {
            storeManager?.indexSynchronizer.remove(observer: self)
        }

        private func fetchLocalNextIndex(completion: @escaping (Result<Int, Error>) -> Void) {
            guard let storeManager else {
                completion(.failure(BaseOperationError.unexpectedDependentResult))
                return
            }
            execute(
                wrapper: storeManager.fetchLocalNextIndex(),
                inOperationQueue: storeManager.operationQueue,
                runningCallbackIn: nil,
                callbackClosure: completion
            )
        }
    }

    func addRemoteNextIndexObserver() {
        indexSynchronizer.add(
            observer: self,
            queue: indexObserverQueue
        ) { [weak self] _, state in
            guard
                let self,
                let state,
                !state.isSynchronizing,
                !state.isCachedValue,
                let nextIndex = state.nextIndex
            else {
                return
            }

            execute(
                wrapper: replaceLocalVouchersIfNeeded(remoteNextIndex: nextIndex),
                inOperationQueue: operationQueue,
                runningCallbackIn: nil,
                callbackClosure: { _ in }
            )
        }
    }

    func removeRemoteNextIndexObserver() {
        indexSynchronizer.remove(observer: self)
    }

    func replaceLocalVouchersIfNeeded(
        remoteNextIndex: Int
    ) -> CompoundOperationWrapper<Void> {
        let localNextIndexWrapper = fetchLocalNextIndex()

        let replaceIfNeededWrapper: CompoundOperationWrapper<Void>
        replaceIfNeededWrapper = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else {
                return .createWithError(BaseOperationError.unexpectedDependentResult)
            }

            let localNextIndex = try localNextIndexWrapper.targetOperation.extractNoCancellableResultData()

            if localNextIndex != remoteNextIndex {
                logger.debug("Remote and local indices mismatch, going to replace local vouchers")
                return replaceLocalVouchers(upToNextIndex: remoteNextIndex)
            } else {
                return .createWithResult(())
            }
        }
        replaceIfNeededWrapper.addDependency(wrapper: localNextIndexWrapper)

        return .init(
            targetOperation: replaceIfNeededWrapper.targetOperation,
            dependencies: replaceIfNeededWrapper.dependencies
                + localNextIndexWrapper.allOperations
        )
    }

    func fetchLocalNextIndex() -> CompoundOperationWrapper<Int> {
        let typePredicate = NSPredicate(
            format: "%K == %@",
            #keyPath(CDLocalPrivacyVoucher.type),
            type.rawValue
        )
        let maxIndexPredicate = NSPredicate(
            format: "%K == max(%K)",
            #keyPath(CDLocalPrivacyVoucher.index),
            #keyPath(CDLocalPrivacyVoucher.index)
        )
        let filter = NSCompoundPredicate(
            type: .and,
            subpredicates: [typePredicate, maxIndexPredicate]
        )
        let repository = repositoryFactory.createLocalVoucherRepository(forFilter: filter)
        let voucherWithMaxIndexOperation = repository.fetchAllOperation(with: RepositoryFetchOptions())

        let mapResultOperation = ClosureOperation<Int> {
            let fetchResult = try voucherWithMaxIndexOperation.extractNoCancellableResultData()
            let nextIndex = (fetchResult.first?.index ?? -1) + 1
            return nextIndex
        }
        mapResultOperation.addDependency(voucherWithMaxIndexOperation)

        return .init(
            targetOperation: mapResultOperation,
            dependencies: [voucherWithMaxIndexOperation]
        )
    }

    func replaceLocalVouchers(upToNextIndex nextIndex: Int) -> CompoundOperationWrapper<Void> {
        let repository = repositoryFactory.createLocalVoucherRepository(forFilter: NSPredicate(
            format: "%K == %@",
            #keyPath(CDLocalPrivacyVoucher.type),
            type.rawValue
        ))

        guard nextIndex > 0 else {
            return .init(targetOperation: repository.deleteAllOperation())
        }

        let generateVoucherOperation = ClosureOperation<[LocalPrivacyVoucher]> { [generator, type] in
            var vouchers = [LocalPrivacyVoucher]()

            for index in 0 ..< nextIndex {
                try vouchers.append(
                    generator.generateLocalVoucher(with: type, index: index)
                )
            }

            return vouchers
        }

        let replaceOperation = repository.replaceOperation {
            try generateVoucherOperation.extractNoCancellableResultData()
        }
        replaceOperation.addDependency(generateVoucherOperation)

        return .init(
            targetOperation: replaceOperation,
            dependencies: [generateVoucherOperation]
        )
    }
}
