import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService
import Individuality
import KeyDerivation

protocol GameTerminationServicing {
    func offBoardWrapper() -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>
}

final class GameTerminationService {
    private let extrinsicOriginFactory: CandidateOriginFactoryProtocol
    private let extrinsicMonitoring: ExtrinsicSubmitMonitorFactoryProtocol
    private let wallet: WalletManaging
    private let chain: ChainProtocol

    init(
        extrinsicOriginFactory: CandidateOriginFactoryProtocol,
        extrinsicMonitoring: ExtrinsicSubmitMonitorFactoryProtocol,
        wallet: WalletManaging,
        chain: ChainProtocol
    ) {
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.extrinsicMonitoring = extrinsicMonitoring
        self.wallet = wallet
        self.chain = chain
    }
}

extension GameTerminationService: GameTerminationServicing {
    func offBoardWrapper() -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        do {
            let origin = try extrinsicOriginFactory.createSignedScoreAsParticipant(
                for: wallet,
                chain: chain
            )
            let offBoardCall = GamePallet.OffBoardCall().runtimeCall()
            return extrinsicMonitoring.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { try $0.adding(call: offBoardCall) },
                origin: origin,
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )
        } catch {
            return .createWithError(error)
        }
    }
}
