import Foundation
import Foundation_iOS
import Keystore_iOS
import ChainRegistry
import EventCenter

@MainActor
enum TattooListViewFactory {
    static func createView() -> TattooListViewProtocol? {
        let state = ProofOfInkFlowState(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            userStorageFacade: UserDataStorageFacade.shared,
            eventCenter: EventCenter.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        )

        return createView(for: state)
    }

    static func createView(
        for state: ProofOfInkFlowStateProtocol
    ) -> TattooListViewProtocol? {
        let dimAsset = AppConfig.Assets.dimAsset

        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        guard
            let dimChain = chainRegistry.getChain(for: dimAsset.chainId),
            let dimAsset = dimChain.chainAsset(for: dimAsset.assetId),
            let interactor = createInteractor(state: state),
            let peopleChain = chainRegistry.getChain(for: AppConfig.Chains.chatChain),
            let candidateAccountId = try? walletRepo.candidate().fetchAccount(
                for: peopleChain
            ).accountId,
            let utilityAssetInfo = peopleChain.utilityAsset()?.digitalDollarDisplayInfo // TODO: unclear
        else {
            return nil
        }

        let wireframe = TattooListWireframe(state: state)
        let userInkChoiceProvider = UserInkChoiceProvider()

        let balanceViewModelFactory = PrimitiveBalanceViewModelFactory(
            targetAssetInfo: utilityAssetInfo,
            formatterFactory: AssetBalanceFormatterFactory()
        )

        let confirmDepositViewModelFactory = ConfirmDepositViewModelFactory(chainAsset: dimAsset)

        let depositDetailsViewModelFactory = TattooDepositDetailsViewModelFactory(
            balanceViewModelFactory: balanceViewModelFactory,
            confirmDepositViewModelFactory: confirmDepositViewModelFactory
        )

        let presenter = TattooListPresenter(
            interactor: interactor,
            wireframe: wireframe,
            candidateAccountId: candidateAccountId,
            viewModelFactory: TattooListViewModelFactory(userInkChoiceProvider: userInkChoiceProvider),
            balanceViewModelFactory: balanceViewModelFactory,
            depositDetailsViewModelFactory: depositDetailsViewModelFactory,
            logger: Logger.shared
        )

        let view = TattooListViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }

    private static func createInteractor(
        state: ProofOfInkFlowStateProtocol
    ) -> TattooListInteractor? {
        let chatChain = AppConfig.Chains.chatChain
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let extrinsicMonitorFacade = ExtrinsicSubmissionMonitorFacade.default()
        let walletRepo: WalletManagerRepositoryProtocol = .shared

        guard
            let chain = chainRegistry.getChain(for: chatChain),
            let connection = chainRegistry.getConnection(for: chain.chainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chain.chainId),
            let extrinsicMonitor = try? extrinsicMonitorFacade.createMonitorFactory(chain: chain),
            let selectedWallet = try? walletRepo.candidate()
        else {
            return nil
        }

        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        let extrinsicOriginFactory = ExtrinsicOriginFactory.personCandidate()

        let extrinsicServiceFactory = extrinsicMonitorFacade.extrinsicServiceFactory
        let tattooTerminationService = TattooTerminationService(
            extrinsicOriginFactory: extrinsicOriginFactory,
            extrinsicMonitoring: extrinsicMonitor,
            state: state,
            wallet: selectedWallet,
            chain: chain
        )

        return TattooListInteractor(
            selectedWallet: selectedWallet,
            chain: chain,
            connection: connection,
            runtimeProvider: runtimeProvider,
            flowState: state,
            proofOfInkFactory: ProofOfInkOperationFactory(operationQueue: operationQueue),
            jsonLocalSubscriptionFactory: JsonDataProviderFactory.shared,
            requiredBalanceFactory: ProofOfInkBalanceOperationFactory(
                extrinsicServiceFactory: extrinsicServiceFactory,
                extrinsicOriginFactory: extrinsicOriginFactory
            ),
            operationQueue: operationQueue,
            tattooTerminationService: tattooTerminationService
        )
    }
}
