import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService
import Individuality
import KeyDerivation

protocol AirdropClaimServicing {
    func submitClaim(
        gameIndex: UInt32,
        beneficiary: AccountId,
        usesScoreAlias: Bool
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission>
}

final class AirdropClaimSubmitService: AirdropClaimServicing {
    private let candidateWallet: WalletManaging
    private let scoreWallet: WalletManaging
    private let chain: ChainProtocol
    private let extrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let candidateOriginFactory: CandidateOriginFactoryProtocol
    private let personhoodOriginFactory: PersonhoodOriginFactoryProtocol

    init(
        candidateWallet: WalletManaging,
        scoreWallet: WalletManaging,
        chain: ChainProtocol,
        extrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        candidateOriginFactory: CandidateOriginFactoryProtocol,
        personhoodOriginFactory: PersonhoodOriginFactoryProtocol
    ) {
        self.candidateWallet = candidateWallet
        self.scoreWallet = scoreWallet
        self.chain = chain
        self.extrinsicSubmitMonitor = extrinsicSubmitMonitor
        self.candidateOriginFactory = candidateOriginFactory
        self.personhoodOriginFactory = personhoodOriginFactory
    }
}

extension AirdropClaimSubmitService {
    func submitClaim(
        gameIndex: UInt32,
        beneficiary: AccountId,
        usesScoreAlias: Bool
    ) -> CompoundOperationWrapper<ExtrinsicMonitorSubmission> {
        do {
            return try extrinsicSubmitMonitor.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { builder in
                    let call = GamePallet.ClaimAirdropCall(
                        gameIndex: gameIndex,
                        airdropIndex: 0,
                        beneficiary: beneficiary
                    )
                    return try builder.adding(call: call.runtimeCall())
                },
                origin: makeOrigin(usesScoreAlias: usesScoreAlias),
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )
        } catch {
            return .createWithError(error)
        }
    }
}

private extension AirdropClaimSubmitService {
    func makeOrigin(usesScoreAlias: Bool) throws -> ExtrinsicOriginDefining {
        if usesScoreAlias {
            try personhoodOriginFactory.createAsPersonalAliasWithAccount(
                input: .init(
                    wallet: scoreWallet,
                    chain: chain,
                    context: Data(PalletContext.score.utf8),
                    blockHash: nil
                )
            )
        } else {
            try candidateOriginFactory.createSignedScoreAsParticipant(
                for: candidateWallet,
                chain: chain
            )
        }
    }
}
