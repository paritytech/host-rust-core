import Foundation
import Operation_iOS
import Individuality
import ExtrinsicService
import KeyDerivation
import ChainRegistry

protocol TattooApplyOperationFactoryProtocol {
    func createApplyOperation() -> BaseOperation<Void>
}

final class TattooApplyOperationFactory: TattooApplyOperationFactoryProtocol {
    let selectedWallet: WalletManaging
    let chain: ChainModel
    let extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol
    let extrinsicOriginFactory: ExtrinsicOriginFactoryProtocol
    let logger: LoggerProtocol

    init(
        selectedWallet: WalletManaging,
        chain: ChainModel,
        extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol,
        extrinsicOriginFactory: ExtrinsicOriginFactoryProtocol,
        logger: LoggerProtocol
    ) {
        self.selectedWallet = selectedWallet
        self.chain = chain
        self.extrinsicServiceFactory = extrinsicServiceFactory
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.logger = logger
    }

    func createApplyOperation() -> BaseOperation<Void> {
        do {
            let extrinsicService = try extrinsicServiceFactory.createExtrinsicService(chain: chain)
            let origin = try extrinsicOriginFactory.createSignedOrigin(
                for: selectedWallet,
                chain: chain
            )

            let builderClosure: ExtrinsicBuilderClosure = { builder in
                try builder.adding(call: ProofOfInkPallet.ApplyCall().runtimeCall())
            }

            return AsyncClosureOperation { [logger] completion in
                extrinsicService.submit(
                    builderClosure,
                    origin: origin,
                    runningIn: .global()
                ) { result in
                    switch result {
                    case let .success(extrinsicResult):
                        logger.debug("Apply result: \(extrinsicResult)")
                        completion(.success(()))
                    case let .failure(error):
                        logger.error("Failed to apply: \(error)")
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            return .createWithError(error)
        }
    }
}
