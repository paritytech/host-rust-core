import Foundation
import Operation_iOS
import SubstrateSdk
import Individuality
import ExtrinsicService
import KeyDerivation

protocol TattooTerminateServicing {
    func flakeOut() -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>
}

final class TattooTerminationService {
    enum TattooTerminationServiceError: Error {
        case failedToResolveCandidateType
    }

    private let extrinsicOriginFactory: CandidateOriginFactoryProtocol
    private let extrinsicMonitoring: ExtrinsicSubmitMonitorFactoryProtocol
    private let candidateTypeProvider: () -> PersonRegistration.CandidateType?
    private let wallet: WalletManaging
    private let chain: ChainProtocol

    init(
        extrinsicOriginFactory: CandidateOriginFactoryProtocol,
        extrinsicMonitoring: ExtrinsicSubmitMonitorFactoryProtocol,
        state: ProofOfInkFlowStateProtocol,
        wallet: WalletManaging,
        chain: ChainProtocol
    ) {
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.extrinsicMonitoring = extrinsicMonitoring
        candidateTypeProvider = { state.candidateType }
        self.wallet = wallet
        self.chain = chain
    }

    init(
        extrinsicOriginFactory: CandidateOriginFactoryProtocol,
        extrinsicMonitoring: ExtrinsicSubmitMonitorFactoryProtocol,
        candidate: ProofOfInkPallet.Candidate,
        wallet: WalletManaging,
        chain: ChainProtocol
    ) {
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.extrinsicMonitoring = extrinsicMonitoring
        let candidateType = PersonRegistration.CandidateType(candidate: candidate)
        candidateTypeProvider = { candidateType }
        self.wallet = wallet
        self.chain = chain
    }
}

extension TattooTerminationService: TattooTerminateServicing {
    func flakeOut() -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        do {
            guard let candidateType = candidateTypeProvider() else {
                throw TattooTerminationServiceError.failedToResolveCandidateType
            }

            let origin = try extrinsicOriginFactory.createPersonRegistrationDefinition(
                for: candidateType,
                wallet: wallet,
                chain: chain
            )

            let flakeOutCall = ProofOfInkPallet.FlakeOutCall().runtimeCall()
            return extrinsicMonitoring.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { try $0.adding(call: flakeOutCall) },
                origin: origin,
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )
        } catch {
            return .createWithError(error)
        }
    }
}
