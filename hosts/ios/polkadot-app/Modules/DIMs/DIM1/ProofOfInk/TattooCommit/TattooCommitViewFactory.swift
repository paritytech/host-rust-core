import Foundation
import KeyDerivation
import Individuality
import ChainRegistry

@MainActor
enum TattooCommitViewFactory {
    static func createView(
        for state: ProofOfInkFlowStateProtocol,
        choice: ProofOfInk.Choice
    ) -> TattooCommitViewProtocol? {
        guard let interactor = createInteractor(for: choice, state: state) else {
            return nil
        }

        let wireframe = TattooCommitWireframe(state: state)

        let presenter = TattooCommitPresenter(
            interactor: interactor,
            wireframe: wireframe,
            choice: choice,
            viewModelFactory: TattooCommitViewModelFactory(),
            logger: Logger.shared
        )

        let view = TattooCommitViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }

    private static func createInteractor(
        for choice: ProofOfInk.Choice,
        state: ProofOfInkFlowStateProtocol
    ) -> TattooCommitInteractor? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        )

        let originFactory = ExtrinsicOriginFactory.personCandidate()
        let walletRepo: WalletManagerRepositoryProtocol = .shared

        guard
            let selectedWallet = try? walletRepo.candidate(),
            let peopleChain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
            let extrinsicSubmissionFactory = try? extrinsicSubmissionFacade.createMonitorFactory(chain: peopleChain),
            let peopleConnection = chainRegistry.getConnection(for: peopleChain.chainId),
            let peopleRuntimeProvider = chainRegistry.getRuntimeProvider(for: peopleChain.chainId),
            let bulletinChain = chainRegistry.getChain(for: AppConfig.Chains.bulletInChain),
            let bulletinRuntimeProvider = chainRegistry.getRuntimeProvider(for: bulletinChain.chainId),
            let candidateType = state.candidateType,
            let extrinsicOrigin = try? originFactory.createPersonRegistrationDefinition(
                for: candidateType,
                wallet: selectedWallet,
                chain: peopleChain
            ) else {
            return nil
        }

        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let commitAvailabilityService = TattooCommitAvailabilityService(
            connection: peopleConnection,
            runtimeProvider: peopleRuntimeProvider,
            operationQueue: operationQueue
        )

        return .init(
            choice: choice,
            peopleChain: peopleChain,
            peopleConnection: peopleConnection,
            peopleRuntimeProvider: peopleRuntimeProvider,
            bulletinChain: bulletinChain,
            bulletinRuntimeProvider: bulletinRuntimeProvider,
            proofOfInkState: state,
            commitAvailabilityService: commitAvailabilityService,
            selectedWallet: selectedWallet,
            extrinsicSubmissionFactory: extrinsicSubmissionFactory,
            extrinsicOrigin: extrinsicOrigin,
            operationQueue: operationQueue,
            jsonLocalSubscriptionFactory: JsonDataProviderFactory.shared
        )
    }
}
