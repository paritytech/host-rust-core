import Foundation
import Operation_iOS
import BigInt
import SubstrateSdk
import ExtrinsicService
import SubstrateStateCall
import SubstrateStorageQuery
import Individuality
import KeyDerivation
import ChainRegistry

protocol GamePalletBalanceFactoryProtocol {
    func flowRequiredBalanceWrapper() -> CompoundOperationWrapper<Balance>
}

final class GamePalletBalanceOperationFactory {
    let extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol
    let extrinsicOriginFactory: CandidateOriginFactoryProtocol
    let stateCallFactory: StateCallRequestFactoryProtocol
    let wallet: WalletManaging
    let chain: ChainModel
    let connection: ChainConnection
    let runtimeProvider: RuntimeProviderProtocol

    init(
        extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol,
        extrinsicOriginFactory: CandidateOriginFactoryProtocol,
        stateCallFactory: StateCallRequestFactoryProtocol,
        wallet: WalletManaging,
        chain: ChainModel,
        connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol
    ) {
        self.extrinsicServiceFactory = extrinsicServiceFactory
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.stateCallFactory = stateCallFactory
        self.wallet = wallet
        self.chain = chain
        self.connection = connection
        self.runtimeProvider = runtimeProvider
    }

    private func createDepositCallWrapper(
        for connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<Balance> {
        let coderFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<StringScaleMapper<Balance>> = stateCallFactory.createWrapper(
            for: "PalletGameApi_play_deposit",
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

extension GamePalletBalanceOperationFactory: GamePalletBalanceFactoryProtocol {
    func flowRequiredBalanceWrapper() -> CompoundOperationWrapper<Balance> {
        do {
            let extrinsicOrigin = try extrinsicOriginFactory.createSignedScoreAsParticipant(
                for: wallet,
                chain: chain
            )

            let feeWrapper = try extrinsicServiceFactory.createOperationFactory(
                chain: chain
            )
            .estimateFeeOperation(
                { builder in
                    // Airdrop proof is omitted: sign-up is `Pays::No`, and the required balance
                    // adds a `2 * fee` buffer plus deposits, so the proof length does not affect it.
                    let call = GamePallet
                        .SignUpWithAccountCall(
                            identifierKey: Data.zeroAccountId(of: Chat.OnChainEncryptionIdentifier.containerSize),
                            airdrops: nil
                        )
                    return try builder.adding(call: call.runtimeCall())
                },
                origin: extrinsicOrigin,
                payingIn: nil
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

                return 2 * fee + reserveDeposit + existentialDeposit
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
