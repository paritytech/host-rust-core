import Foundation
import SubstrateSdk
import NovaCrypto
import Operation_iOS
import ExtrinsicService
import Individuality
import KeyDerivation
import ChainRegistry

enum CleanCaseError: Error {
    case failedToCleanCases([Error])
}

protocol CleanCaseServicing: AnyObject {
    func cleanCases(
        _ casesToClean: MobRulePallet.DoneCasesResult,
        maxClaimableVotes: ClaimableVotesLimit,
        blockHash: Data?,
        completion: @escaping (Result<Void, CleanCaseError>) -> Void
    )
}

final class CleanCaseService: CleanCaseServicing {
    private let chain: ChainModel
    private let extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol
    private let extrinsicOriginFactory: PersonhoodOriginFactoryProtocol
    private let selectedWallet: WalletManaging
    private let dispatchQueue: DispatchQueue
    private let logger: LoggerProtocol

    private var extrinsicService: ExtrinsicServiceProtocol?

    init(
        chain: ChainModel,
        extrinsicServiceFactory: ExtrinsicServiceFactoryProtocol,
        extrinsicOriginFactory: PersonhoodOriginFactoryProtocol,
        selectedWallet: WalletManaging = WalletManagerRepository.shared.mobRuleAlias(),
        logger: LoggerProtocol = Logger.shared,
        dispatchQueue: DispatchQueue = DispatchQueue(label: "io.polkadot.service.cleancase.\(UUID().uuidString)")
    ) {
        self.chain = chain
        self.extrinsicServiceFactory = extrinsicServiceFactory
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.selectedWallet = selectedWallet
        self.logger = logger
        self.dispatchQueue = dispatchQueue
    }

    func cleanCases(
        _ casesToClean: MobRulePallet.DoneCasesResult,
        maxClaimableVotes: ClaimableVotesLimit,
        blockHash _: Data?,
        completion: @escaping (Result<Void, CleanCaseError>) -> Void
    ) {
        guard
            let service = try? extrinsicServiceFactory.createExtrinsicService(chain: chain),
            let origin = try? extrinsicOriginFactory.createAsPersonalAliasWithAccount(
                input: .init(
                    wallet: selectedWallet,
                    chain: chain,
                    context: Data(PalletContext.mobRule.utf8),
                    blockHash: nil
                )
            )
        else {
            return
        }

        extrinsicService = service

        let doneCaseIndexes = casesToClean.map(\.key)
        let batches = splitCases(doneCaseIndexes, limit: maxClaimableVotes)
        let totalExtrinsics = batches.count

        let buildClosure: ExtrinsicBuilderIndexedClosure = { builder, index in
            let caseIndices = batches[index]

            let claimVote = MobRulePallet.ClaimVotesCall(
                caseIndices: caseIndices.map { String($0) }
            )

            return try builder.adding(call: claimVote.runtimeCall())
        }

        let completion: ExtrinsicSubmitIndexedClosure = { [weak self] indexedResult in
            guard let self else {
                return
            }

            if indexedResult.errors().isEmpty {
                completion(.success(()))
                logger.debug("Claim votes submitted successfully for all indexes")
            } else {
                logger.error("Calim votes failed for indexes: \(indexedResult.failedIndexes())")
                logger.error("Errors: \(indexedResult.errors())")
                completion(.failure(.failedToCleanCases(indexedResult.errors())))
            }
        }

        extrinsicService?.submit(
            buildClosure,
            origin: origin,
            runningIn: dispatchQueue,
            numberOfExtrinsics: totalExtrinsics,
            completion: completion
        )
    }

    private func splitCases(
        _ cases: [MobRulePallet.CaseIndex],
        limit: ClaimableVotesLimit
    ) -> [[MobRulePallet.CaseIndex]] {
        var result: [[MobRulePallet.CaseIndex]] = []
        var currentBatch: [MobRulePallet.CaseIndex] = []

        for caseIndex in cases {
            if currentBatch.count == limit {
                result.append(currentBatch)
                currentBatch = []
            }
            currentBatch.append(caseIndex)
        }

        if !currentBatch.isEmpty {
            result.append(currentBatch)
        }

        return result
    }
}
