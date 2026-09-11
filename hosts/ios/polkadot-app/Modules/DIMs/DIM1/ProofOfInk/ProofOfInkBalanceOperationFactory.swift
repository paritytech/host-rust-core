import Foundation
import Operation_iOS
import BigInt
import SubstrateSdk
import SubstrateStateCall
import ExtrinsicService
import SubstrateStorageQuery
import Individuality
import KeyDerivation
import ChainRegistry

protocol ProofOfInkBalanceFactoryProtocol {
    func flowRequiredBalanceWrapper(
        for wallet: WalletManaging,
        chain: ChainModel,
        connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<Balance>
}

final class ProofOfInkBalanceOperationFactory {
    let extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol
    let extrinsicOriginFactory: ExtrinsicOriginFactoryProtocol
    let stateCallFactory: StateCallRequestFactoryProtocol

    init(
        extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol,
        extrinsicOriginFactory: ExtrinsicOriginFactoryProtocol,
        stateCallFactory: StateCallRequestFactoryProtocol = StateCallRequestFactory()
    ) {
        self.extrinsicServiceFactory = extrinsicServiceFactory
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.stateCallFactory = stateCallFactory
    }

    private func createDepositCallWrapper(
        for connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<Balance> {
        let coderFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<StringScaleMapper<Balance>> = stateCallFactory.createWrapper(
            for: "ProofOfInkApi_candidacy_deposit",
            paramsClosure: nil,
            codingFactoryClosure: { try coderFactoryOperation.extractNoCancellableResultData() },
            connection: connection,
            queryType: KnownType.balance.name
        )

        fetchWrapper.addDependency(operations: [coderFactoryOperation])

        let mappingOperation = ClosureOperation<Balance> {
            try fetchWrapper.targetOperation.extractNoCancellableResultData().value
        }

        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingHead(operations: [coderFactoryOperation])
            .insertingTail(operation: mappingOperation)
    }
}

extension ProofOfInkBalanceOperationFactory: ProofOfInkBalanceFactoryProtocol {
    func flowRequiredBalanceWrapper(
        for wallet: WalletManaging,
        chain: ChainModel,
        connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<Balance> {
        do {
            let extrinsicOrigin = try extrinsicOriginFactory.createSignedOrigin(
                for: wallet,
                chain: chain
            )

            let feeWrapper = try extrinsicServiceFactory.createOperationFactory(
                chain: chain
            )
            .estimateFeeOperation(
                { builder in
                    let call = ProofOfInkPallet.ApplyCall()
                    return try builder.adding(call: call.runtimeCall())
                },
                origin: extrinsicOrigin,
                payingIn: ChainAssetId(chainId: AppConfig.Chains.chatChain, assetId: 0)
            )

            let reserveDepositWrapper = createDepositCallWrapper(
                for: connection,
                runtimeProvider: runtimeProvider
            )

            let existentialDepositWrapper: CompoundOperationWrapper<BigUInt> = PrimitiveConstantOperation.wrapper(
                for: BalancesPallet.existentialDepositPath,
                runtimeService: runtimeProvider
            )

            let calculateOperation = ClosureOperation<Balance> {
                let fee = try feeWrapper.targetOperation.extractNoCancellableResultData().amount
                let reserveDeposit = try reserveDepositWrapper.targetOperation.extractNoCancellableResultData()
                let existentialDeposit = try existentialDepositWrapper.targetOperation.extractNoCancellableResultData()

                /// in the worst case there 5 operations to do +1 for buffer:
                ///    - apply tattoo
                ///    - commit tattoo
                ///    - submit photo evidence
                ///    - allocate video storage
                ///    - submit video evidence
                let factor = Balance(6)

                return factor * fee + reserveDeposit + existentialDeposit
            }

            calculateOperation.addDependency(existentialDepositWrapper.targetOperation)
            calculateOperation.addDependency(reserveDepositWrapper.targetOperation)
            calculateOperation.addDependency(feeWrapper.targetOperation)

            return existentialDepositWrapper
                .insertingHead(operations: reserveDepositWrapper.allOperations)
                .insertingHead(operations: feeWrapper.allOperations)
                .insertingTail(operation: calculateOperation)
        } catch {
            return .createWithError(error)
        }
    }
}
