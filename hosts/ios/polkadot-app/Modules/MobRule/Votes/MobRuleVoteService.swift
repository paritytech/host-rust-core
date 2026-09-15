import Foundation
import SubstrateSdk
import Operation_iOS
import ExtrinsicService
import Individuality
import KeyDerivation
import ChainRegistry

struct MobRuleVote {
    let caseIndex: MobRulePallet.CaseIndex
    let openCase: MobRulePallet.OpenCase
    let opinion: MobRulePallet.Judgement
    let tattooFamilyId: ProofOfInkPallet.FamilyId?
}

protocol MobRuleVoteServicing: AnyObject {
    func vote(with decision: MobRuleVote) async throws
}

final class MobRuleVoteService: MobRuleVoteServicing {
    private let chain: ChainModel
    private let extrinsicSubmissionFacade: ExtrinsicSubmissionMonitorFacadeProtocol
    private let extrinsicOriginFactory: PersonhoodOriginFactoryProtocol
    private let selectedWallet: WalletManaging
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    private var extrinsicSubmissionFactory: ExtrinsicSubmitMonitorFactoryProtocol?

    init(
        chain: ChainModel,
        extrinsicSubmissionFacade: ExtrinsicSubmissionMonitorFacadeProtocol,
        extrinsicOriginFactory: PersonhoodOriginFactoryProtocol,
        selectedWallet: WalletManaging = WalletManagerRepository.shared.mobRuleAlias(),
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chain = chain
        self.selectedWallet = selectedWallet
        self.extrinsicSubmissionFacade = extrinsicSubmissionFacade
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.operationQueue = operationQueue
        self.logger = logger
    }

    private func setupSubmissionFactory() throws -> ExtrinsicSubmitMonitorFactoryProtocol {
        if let extrinsicSubmissionFactory {
            return extrinsicSubmissionFactory
        }

        let factory = try extrinsicSubmissionFacade.createMonitorFactory(chain: chain)
        extrinsicSubmissionFactory = factory

        return factory
    }

    func vote(with decision: MobRuleVote) async throws {
        let submissionFactory = try setupSubmissionFactory()
        let origin = try extrinsicOriginFactory.createAsPersonalAliasWithAccount(
            input: .init(
                wallet: selectedWallet,
                chain: chain,
                context: Data(PalletContext.mobRule.utf8),
                blockHash: nil
            )
        )

        let extrinsicCall = MobRulePallet.VoteCall(
            caseIndex: decision.caseIndex,
            opinion: decision.opinion
        )

        let wrapper = submissionFactory.submitAndMonitorWrapper(
            extrinsicBuilderClosure: { builder in
                try builder
                    .adding(call: extrinsicCall.runtimeCall())
            },
            origin: origin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )

        let submissionResult = try await wrapper.asyncExecute()

        switch submissionResult.status {
        case let .success(extrinsicHash):
            logger.debug("Vote submission successful: \(extrinsicHash)")
        case let .failure(failedExtrinsic):
            logger.error("Vote submission failed: \(failedExtrinsic)")
            throw failedExtrinsic.error
        }
    }
}
