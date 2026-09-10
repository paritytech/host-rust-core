import Foundation
import SubstrateSdk
import ExtrinsicService
import Keystore_iOS
import KeyDerivation
import SubstrateOperation
import ChainRegistry
import BackgroundExecution
import Products

enum GameReportViewFactory {
    @MainActor
    static func createView(
        flowState: DIM2SharedFlowStateProtocol,
        gameId: Game.Identifier,
        chatId: Chat.Id,
        spaFlowState: SPAFlowState
    ) -> GameReportViewProtocol? {
        guard let components = createComponents(
            flowState: flowState,
            gameId: gameId,
            spaFlowState: spaFlowState
        ) else {
            return nil
        }

        let wireframe = GameReportWireframe(
            chatId: chatId,
            resultsDependencies: components.resultsDependencies
        )

        let viewModelProvider = GameReportViewModelProvider()
        let presenter = GameReportPresenter(
            interactor: components.interactor,
            wireframe: wireframe,
            viewModelProvider: viewModelProvider
        )
        let view = GameReportViewController(presenter: presenter)

        presenter.view = view
        components.interactor.presenter = presenter

        return view
    }

    private struct Components {
        let interactor: GameReportInteractor
        let resultsDependencies: GameResultsDependencies
    }

    private static func createComponents(
        flowState: DIM2SharedFlowStateProtocol,
        gameId: Game.Identifier,
        spaFlowState: SPAFlowState
    ) -> Components? {
        let logger = Logger.shared
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let source = flowState.source
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        guard let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain) else {
            logger.error("Missing chain")
            return nil
        }

        logger.debug(
            "[GameDebug] chain name=\(chain.name) id=\(chain.chainId) "
                + "nodes=\(chain.nodes.map(\.url))"
        )

        let walletRepo: WalletManagerRepositoryProtocol = .shared
        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard
            let candidateWallet = try? walletRepo.candidate(),
            let scoreWallet = try? walletRepo.scoreAlias(),
            let reportVrfManager = try? vrfRepo.fullPerson()
        else {
            logger.error("Failed to resolve game wallets")
            return nil
        }

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: operationQueue,
            logger: logger
        )

        guard let extrinsicSubmitMonitor = try? extrinsicSubmissionFacade.createMonitorFactory(chain: chain) else {
            logger.error("Failed to create extrinsicSubmitMonitor")
            return nil
        }

        guard let candidateAccount = GameAccountFactory.makeAccount(chain: chain, registeredSource: .game) else {
            logger.error("Missing candidate account for game")
            return nil
        }

        guard let reportAccount = GameAccountFactory.makeAccount(chain: chain, registeredSource: source) else {
            logger.error("Missing account for game")
            return nil
        }

        let submitReportService = GameSubmitReportService(
            candidateWallet: candidateWallet,
            scoreWallet: scoreWallet,
            chain: chain,
            extrinsicSubmitMonitor: extrinsicSubmitMonitor,
            candidateOriginFactory: ExtrinsicOriginFactory.personCandidate(),
            personhoodOriginFactory: PersonhoodOriginFactory(
                vrfManager: reportVrfManager,
                chainRegistry: chainRegistry,
                operationQueue: operationQueue,
                logger: logger
            )
        )
        let reportService = GameReportService(
            localPlayerId: reportAccount.accountId,
            registeredSource: source,
            infoSyncService: flowState.gameSyncService,
            submitReportService: submitReportService,
            gameDashboardTelemetry: flowState.gameDashboardTelemetry
        )

        let player = flowState.personDataStore.currentState?.makeAccountOrPerson()
            ?? .account(accountID: candidateAccount.accountId)

        guard let airdropComponents = makeAirdropComponents(
            chain: chain,
            extrinsicSubmitMonitor: extrinsicSubmitMonitor,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue
        ) else {
            logger.error("Failed to create airdrop components")
            return nil
        }

        let claimBeneficiary = (try? walletRepo.depositWallet().getMultiSigner().getAccountId())
            ?? candidateAccount.accountId
        logger.debug(
            "[GameDebug] claim beneficiary=depositWallet(\(claimBeneficiary.toHex(includePrefix: true).prefix(12))…) " +
                "(fallback when no persisted registration)"
        )

        let interactor = GameReportInteractor(
            gameId: gameId,
            infoSyncService: flowState.gameSyncService,
            historySyncService: flowState.gameHistorySyncService,
            reportService: reportService,
            personDataStore: flowState.personDataStore,
            claimBeneficiary: claimBeneficiary,
            claimUsesScoreAlias: source?.isNotGameRecognizedPerson == true,
            player: player,
            backgroundExecutor: ConnectionRetainingExecutor(provider: chainRegistry)
        )

        let resultsDependencies = GameResultsDependencies(
            groupRosterService: airdropComponents.roster,
            prizeService: airdropComponents.prize,
            memberService: airdropComponents.member,
            claimService: airdropComponents.claim,
            nftsSubscriptionService: airdropComponents.nftsSubscription,
            personDataStore: flowState.personDataStore,
            usernameStorage: UsernameStorage(),
            airdropRegistrationStore: AirdropRegistrationStore(),
            spaFlowState: spaFlowState
        )

        return Components(interactor: interactor, resultsDependencies: resultsDependencies)
    }

    private struct AirdropComponents {
        let prize: AirdropPrizeServicing
        let member: GameMemberServicing
        let claim: AirdropClaimServicing
        let roster: GameGroupRosterProviding
        let nftsSubscription: GameNftsSubscriptionServicing
    }

    private static func makeAirdropComponents(
        chain: ChainModel,
        extrinsicSubmitMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue
    ) -> AirdropComponents? {
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard
            let connection = try? chainRegistry.getConnectionOrError(for: chain.chainId),
            let runtimeProvider = try? chainRegistry.getRuntimeProviderOrError(for: chain.chainId),
            let vrfManager = try? vrfRepo.fullPerson(),
            let candidateWallet = try? walletRepo.candidate(),
            let scoreWallet = try? walletRepo.scoreAlias()
        else { return nil }

        let personhoodOriginFactory = PersonhoodOriginFactory(
            vrfManager: vrfManager,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: Logger.shared
        )

        // Prize precision is assumed to be the main asset (see AirdropPrizeService) — read from the
        // chain registry rather than decoded from the prize XCM Location.
        let mainAsset = AppConfig.Assets.mainAsset
        let prizeAssetPrecision = chainRegistry.getChain(for: mainAsset.chainId)?
            .asset(for: mainAsset.assetId)?.precision ?? 0

        return AirdropComponents(
            prize: AirdropPrizeService(
                connection: connection,
                runtimeService: runtimeProvider,
                prizeAssetPrecision: prizeAssetPrecision
            ),
            member: GameMemberService(connection: connection, runtimeService: runtimeProvider),
            claim: AirdropClaimSubmitService(
                candidateWallet: candidateWallet,
                scoreWallet: scoreWallet,
                chain: chain,
                extrinsicSubmitMonitor: extrinsicSubmitMonitor,
                candidateOriginFactory: ExtrinsicOriginFactory.personCandidate(),
                personhoodOriginFactory: personhoodOriginFactory
            ),
            roster: GameGroupRosterService(connection: connection, runtimeService: runtimeProvider),
            nftsSubscription: GameNftsSubscriptionService(
                chainRegistry: chainRegistry,
                chainId: chain.chainId
            )
        )
    }
}
