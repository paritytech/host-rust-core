import Foundation
import KeyDerivation
import ChainRegistry
import UIKit.UIApplication

enum MobRulesFactory {
    @MainActor
    static func create(
        settings: ChatExtensionBotSettings,
        scoreInfoSyncService: ScoreInfoSyncServicing
    ) -> MobRulesChatExtension? {
        guard let interactor = createInteractor(scoreInfoSyncService: scoreInfoSyncService) else {
            Logger.shared.error("Failed to create MobRuleInteractor")
            return nil
        }

        return MobRulesChatExtension(
            settings: settings,
            interactor: interactor,
            wireframe: MobRuleWireframe(application: UIApplication.shared)
        )
    }
}

private extension MobRulesFactory {
    static func createInteractor(scoreInfoSyncService: ScoreInfoSyncServicing) -> MobRuleInteractor? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let logger = Logger.shared
        let chainId = AppConfig.Chains.usernameChain

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: operationQueue,
            logger: logger
        )

        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard
            let chain = chainRegistry.getChain(for: chainId),
            let connection = chainRegistry.getConnection(for: chainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chainId),
            let vrfManager = try? vrfRepo.fullPerson()
        else {
            return nil
        }

        let extrinsicOriginFactory = PersonhoodOriginFactory(
            vrfManager: vrfManager,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )

        return MobRuleInteractor(
            chain: chain,
            caseCleanService: CleanCaseService(
                chain: chain,
                extrinsicServiceFactory: extrinsicSubmissionFacade.extrinsicServiceFactory,
                extrinsicOriginFactory: extrinsicOriginFactory
            ),
            connection: connection,
            runtimeProvider: runtimeProvider,
            voteService: MobRuleVoteService(
                chain: chain,
                extrinsicSubmissionFacade: extrinsicSubmissionFacade,
                extrinsicOriginFactory: extrinsicOriginFactory
            ),
            scoreInfoSyncService: scoreInfoSyncService
        )
    }
}
