import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateOperation
import SubstrateStorageQuery
import ChainRegistry

protocol PrivacyVoucherValueRepositoryProtocol {
    func fetchRewardsVoucherValue(
        forTypePath typePath: ConstantCodingPath,
        chainId: ChainModel.Id
    ) -> CompoundOperationWrapper<Balance>
}

final class PrivacyVoucherValueRepository {
    let runtimeApiOperationFactory: SubstrateRuntimeApiOperationFactory
    let operationQueue: OperationQueue
    let chainRegistry: ChainRegistryProtocol
    let logger: LoggerProtocol

    init(
        runtimeApiOperationFactory: SubstrateRuntimeApiOperationFactory,
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.runtimeApiOperationFactory = runtimeApiOperationFactory
        self.chainRegistry = chainRegistry
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension PrivacyVoucherValueRepository: PrivacyVoucherValueRepositoryProtocol {
    func fetchRewardsVoucherValue(
        forTypePath typePath: ConstantCodingPath,
        chainId: ChainModel.Id
    ) -> CompoundOperationWrapper<Balance> {
        do {
            let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)
            let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

            let constantFetchOperation = StorageConstantOperation<PrivacyVoucherPallet.VoucherType>(
                path: typePath
            )
            constantFetchOperation.configurationBlock = {
                do {
                    constantFetchOperation.codingFactory = try codingFactoryOperation.extractNoCancellableResultData()
                } catch {
                    constantFetchOperation.result = .failure(error)
                }
            }
            constantFetchOperation.addDependency(codingFactoryOperation)

            let valueWrapper = fetchValue(
                for: { try constantFetchOperation.extractNoCancellableResultData() },
                chainId: chainId
            )
            valueWrapper.addDependency(operations: [constantFetchOperation])

            return valueWrapper.insertingHead(operations: [codingFactoryOperation, constantFetchOperation])
        } catch {
            return .createWithError(error)
        }
    }
}

private extension PrivacyVoucherValueRepository {
    func fetchValue(
        for typeClosure: @escaping () throws -> PrivacyVoucherPallet.VoucherType,
        chainId: ChainModel.Id
    ) -> CompoundOperationWrapper<Balance> {
        OperationCombiningService.compoundNonOptionalWrapper(
            operationManager: OperationManager(operationQueue: operationQueue)
        ) { [weak self] in
            let voucherType = try typeClosure()
            self?.logger.debug("Voucher type: \(voucherType)")

            switch voucherType {
            case let .fixed(value):
                return .createWithResult(value)
            case let .variable(voucherId):
                return self?.createVariableValueFetchWrapper(
                    forVoucherId: voucherId,
                    chainId: chainId,
                ) ?? .createWithError(BaseOperationError.unexpectedDependentResult)
            }
        }
    }

    func createVariableValueFetchWrapper(
        forVoucherId voucherId: Data,
        chainId: ChainModel.Id
    ) -> CompoundOperationWrapper<Balance> {
        let fetchWrapper: CompoundOperationWrapper<
            StringScaleMapper<Balance>
        > = runtimeApiOperationFactory.createRuntimeCallWrapper(
            for: chainId,
            path: .init(module: "PrivacyVoucherApi", method: "voucher_value")
        ) { runtimeApi, encoder, context in
            let paramsCount = runtimeApi.method.inputs.count

            guard paramsCount == 1 else {
                throw SubstrateRuntimeApiOperationFactoryError.unexpectedParamsCount
            }

            let originType = runtimeApi.method.inputs[0].paramType

            try encoder.append(
                BytesCodable(wrappedValue: voucherId),
                ofType: String(originType),
                with: context.toRawContext()
            )
        }

        let mappingOperation = ClosureOperation<Balance> {
            try fetchWrapper.targetOperation.extractNoCancellableResultData().value
        }
        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper.insertingTail(operation: mappingOperation)
    }
}
