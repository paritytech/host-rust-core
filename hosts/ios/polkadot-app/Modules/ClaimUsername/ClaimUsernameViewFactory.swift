import Foundation
import Common
import Keystore_iOS
import ExtrinsicService
import KeyDerivation
import ChainRegistry
import Individuality
import SubstrateSdk
import SubstrateStorageQuery
import Operation_iOS

@MainActor
enum ClaimUsernameViewFactory {
    static func createLiteClaimView(
        observer: RootStateObserving
    ) -> ClaimUsernameViewProtocol? {
        guard let hasWallets = try? RootEntropyManager.shared.hasRootEntropy() else {
            return nil
        }

        guard let interactor = createLiteInteractor(hasWallets: hasWallets) else {
            return nil
        }

        let wireframe = ClaimLiteUsernameWireframe(observer: observer)

        let validationFactory = UsernameValidationFactory(presentable: wireframe)
        let presenter = ClaimUsernamePresenter(
            interactor: interactor,
            wireframe: wireframe,
            validationFactory: validationFactory,
            viewModelProvider: ClaimUsernameViewModelFactory(
                recoverable: !hasWallets,
                full: false
            ),
            prefilledUsername: nil,
            logger: Logger.shared
        )

        let view = ClaimLiteUsernameViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter
        validationFactory.view = view

        return view
    }

    static func createFullClaimView(
        registeredData: People.RegisteredData
    ) -> ClaimUsernameViewProtocol? {
        guard let interactor = createFullInteractor(registeredData: registeredData) else {
            return nil
        }

        let wireframe = ClaimFullUsernameWireframe()

        let validationFactory = UsernameValidationFactory(presentable: wireframe)
        let presenter = ClaimUsernamePresenter(
            interactor: interactor,
            wireframe: wireframe,
            validationFactory: validationFactory,
            viewModelProvider: ClaimUsernameViewModelFactory(
                recoverable: false,
                full: true
            ),
            prefilledUsername: registeredData.liteUsername,
            logger: Logger.shared
        )

        let view = ClaimFullUsernameViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter
        validationFactory.view = view

        return view
    }

    private static func createLiteInteractor(hasWallets: Bool) -> ClaimLiteUsernameInteractor? {
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let timeProvider = ChainTimeProvider(
            chainId: AppConfig.Chains.chatChain,
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            storageRequestFactory: StorageRequestFactory(
                remoteFactory: StorageKeyFactory(),
                operationManager: OperationManager(operationQueue: operationQueue)
            )
        )
        let dependencies = ClaimLiteUsernameDependency(
            walletSetupManagerFactory: { createWalletManager() },
            registrationParamsFactory: { mainWallet, liteVrfManager in
                try LitePersonParamsFactory(
                    mainWallet: mainWallet,
                    liteVrfManager: liteVrfManager,
                    chatEncryptorManager: ChatEncryptionManager()
                )
            },
            chainTimeProvider: { timeProvider },
            usernameOperationFactory: { UsernameOperationFactory(tokenProvider: JWTTokenManager.shared) },
            usernameStorage: { UsernameStorage() },
            walletRepo: .shared,
            vrfRepo: .shared
        )

        return ClaimLiteUsernameInteractor(
            walletCreated: hasWallets,
            dependencies: dependencies,
            logger: Logger.shared
        )
    }

    private static func createWalletManager() -> WalletSetupManaging {
        WalletSetupManager(
            mnemonicGenerator: IRMnemonicCreator(),
            mnemonicBackupHelper: MnemonicBackupHelper(),
            entropyManager: RootEntropyManager.shared,
            logger: Logger.shared
        )
    }

    private static func createFullInteractor(
        registeredData: People.RegisteredData
    ) -> ClaimFullUsernameInteractor? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let logger = Logger.shared
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: operationQueue,
            logger: logger
        )

        // Full claim is only reachable after lite onboarding cached the TLD, so the built-in
        // accounts resolve synchronously here.
        guard
            let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
            let extrinsicSubmitMonitor = try? extrinsicSubmissionFacade.createMonitorFactory(chain: chain),
            let fullVRFManager = try? vrfRepo.fullPerson(),
            let liteWallet = try? walletRepo.main()
        else {
            return nil
        }

        let litePersonOriginFactory = PersonLiteOriginFactory(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )

        let gameExtrinsicOriginFactory = PersonhoodOriginFactory(
            vrfManager: fullVRFManager,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )

        let claimService = FullUsernameClaimService(
            chain: chain,
            registeredData: registeredData,
            extrinsicSubmitMonitor: extrinsicSubmitMonitor,
            extrinsicOriginFactory: gameExtrinsicOriginFactory,
            litePersonOriginFactory: litePersonOriginFactory,
            liteWallet: liteWallet,
            resourcesWallet: walletRepo.resourcesAlias()
        )

        return ClaimFullUsernameInteractor(
            registeredData: registeredData,
            claimService: claimService
        )
    }
}
