import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService
import ChainRegistry

protocol PrivacyVoucherRedeemCreditServicing {
    func redeemCredit(with input: RedeemCreditInput<some RuntimeCallable>)
}

final class PrivacyVoucherRedeemCreditService {
    private let chainId: ChainModel.Id
    private let voucherValueRepository: PrivacyVoucherValueRepositoryProtocol
    private let extrinsicSubmissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let voucherManager: PrivacyVoucherStoreManaging
    private let operationQueue: OperationQueue
    private let workQueue: DispatchQueue
    private let logger: LoggerProtocol

    private var callStore = CancellableCallStore()

    init(
        extrinsicSubmissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        voucherManager: PrivacyVoucherStoreManaging,
        chainId: ChainId, // people chain
        voucherValueRepository: PrivacyVoucherValueRepositoryProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        workQueue: DispatchQueue = .global(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chainId = chainId
        self.voucherValueRepository = voucherValueRepository
        self.extrinsicSubmissionMonitor = extrinsicSubmissionMonitor
        self.voucherManager = voucherManager
        self.operationQueue = operationQueue
        self.workQueue = workQueue
        self.logger = logger
    }
}

extension PrivacyVoucherRedeemCreditService: PrivacyVoucherRedeemCreditServicing {
    func redeemCredit(with input: RedeemCreditInput<some RuntimeCallable>) {
        guard input.credit > 0 else {
            logger.debug("No credit to redeem")
            return
        }

        guard !callStore.hasCall else {
            logger.debug("Already registering vouchers. Skipping")
            return
        }

        let voucherValueWrapper = voucherValueWrapper(inputValue: input.voucherValue)

        let registrationWrapper: CompoundOperationWrapper<Void> = OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            guard let self else { throw BaseOperationError.unexpectedDependentResult }
            let voucherValue = try voucherValueWrapper.targetOperation.extractNoCancellableResultData()
            logger.debug("Voucher value: \(voucherValue)")
            return createVouchersWrapper(with: input, voucherValue: voucherValue)
        }
        registrationWrapper.addDependency(wrapper: voucherValueWrapper)

        let wrapper = registrationWrapper.insertingHead(operations: voucherValueWrapper.allOperations)

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: callStore,
            runningCallbackIn: workQueue
        ) { [weak self] result in
            switch result {
            case .success:
                self?.logger.debug("Vouchers successfully registered")
            case let .failure(error):
                self?.logger.error("Vouchers registration failed: \(error)")
            }
        }
    }
}

private extension PrivacyVoucherRedeemCreditService {
    func voucherValueWrapper(inputValue: RedeemCreditVoucherValue) -> CompoundOperationWrapper<Balance> {
        switch inputValue {
        case let .hardcoded(value):
            logger.debug("Hardcoded voucher value: \(value)")
            return .createWithResult(value)
        case let .pathToFetch(voucherTypePath):
            logger.debug("Going to fetch voucher value for type path: \(voucherTypePath)")
            return voucherValueRepository.fetchRewardsVoucherValue(
                forTypePath: voucherTypePath,
                chainId: chainId
            )
        }
    }

    func createVouchersWrapper(
        with input: RedeemCreditInput<some RuntimeCallable>,
        voucherValue: Balance
    ) -> CompoundOperationWrapper<Void> {
        let vouchersCount = input.credit / voucherValue

        guard vouchersCount > 0 else {
            logger.debug("Not enough credit for voucher")
            return .createWithResult(())
        }

        guard vouchersCount <= Balance(Int.max) else {
            logger.error("Too much vouchers")
            return .createWithResult(())
        }

        let numberOfVoucher = Int(vouchersCount)

        logger.debug("Will start vouchers registration: \(numberOfVoucher)")

        let optVouchersWrapper: CompoundOperationWrapper<ExtrinsicMonitorSubmission>?
        optVouchersWrapper = (0 ..< numberOfVoucher).reduce(nil) { prevWrapper, _ in
            guard let prevWrapper else {
                return createVoucherWrapper(with: input)
            }

            let nextWrapper = OperationCombiningService<ExtrinsicMonitorSubmission>.compoundNonOptionalWrapper(
                operationManager: OperationManager(operationQueue: operationQueue)
            ) { [weak self] in
                guard let self else { throw BaseOperationError.unexpectedDependentResult }
                _ = try prevWrapper.targetOperation.extractNoCancellableResultData()
                logger.debug("Did complete voucher registration")
                return createVoucherWrapper(with: input)
            }
            nextWrapper.addDependency(wrapper: prevWrapper)

            return nextWrapper.insertingHead(operations: prevWrapper.allOperations)
        }

        guard let voucherWrapper = optVouchersWrapper else {
            logger.error("Unexpected empty wrapper")
            return .createWithResult(())
        }

        let mappingOperation = ClosureOperation {
            _ = try voucherWrapper.targetOperation.extractNoCancellableResultData()
        }
        mappingOperation.addDependency(voucherWrapper.targetOperation)

        return voucherWrapper.insertingTail(operation: mappingOperation)
    }

    func createVoucherWrapper(
        with input: RedeemCreditInput<some Any>
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        voucherManager.registerPrivacyVouchers(
            withCount: 1,
            registerWrapperFactory: { [weak self] vouchers in
                guard let self, vouchers.count == 1 else {
                    throw BaseOperationError.unexpectedDependentResult
                }

                let voucher = vouchers[0]

                do {
                    let origin = try input.originFactory()

                    logger.debug("Will submit redeem extrinsic")

                    return extrinsicSubmissionMonitor.submitAndMonitorWrapper(
                        extrinsicBuilderClosure: { builder in
                            try builder.adding(call: input.callFactory(voucher))
                        },
                        origin: origin,
                        params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
                    )
                } catch {
                    return .createWithError(error)
                }
            }
        )
    }
}

final class RedeemCreditInput<Call: RuntimeCallable> {
    let credit: Balance
    let voucherValue: RedeemCreditVoucherValue
    let originFactory: () throws -> any ExtrinsicOriginDefining
    let callFactory: (LocalPrivacyVoucher) throws -> Call

    init(
        credit: Balance,
        voucherValue: RedeemCreditVoucherValue,
        originFactory: @escaping () throws -> any ExtrinsicOriginDefining,
        callFactory: @escaping (LocalPrivacyVoucher) throws -> Call
    ) {
        self.credit = credit
        self.voucherValue = voucherValue
        self.originFactory = originFactory
        self.callFactory = callFactory
    }
}

enum RedeemCreditVoucherValue {
    case hardcoded(Balance)
    case pathToFetch(ConstantCodingPath)
}
