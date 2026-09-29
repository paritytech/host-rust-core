import Foundation
import Operation_iOS
import SubstrateSdk
import Keystore_iOS
import OperationExt
import Individuality
import KeyDerivation
import AssetsManagement
import ChainRegistry

final class TattooListInteractor: AnyProviderAutoCleaning {
    weak var presenter: TattooListInteractorOutputProtocol?

    #if TESTNET_FEATURE
        private let topUpService: TopUpService? = TopUpService.create(for: AppConfig.Assets.dimAsset)
        private var topUpTask: Task<Void, Error>?
    #endif

    let selectedWallet: WalletManaging
    let chain: ChainModel
    let connection: ChainConnection
    let runtimeProvider: RuntimeProviderProtocol
    let flowState: ProofOfInkFlowStateProtocol
    let proofOfInkFactory: ProofOfInkOperationFactoryProtocol
    let jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol
    let requiredBalanceFactory: ProofOfInkBalanceFactoryProtocol
    let operationQueue: OperationQueue
    let logger: LoggerProtocol

    let tattooTerminationService: TattooTerminateServicing

    private var tattooMetadataProviders: [AnySingleValueProvider<TattooMetadata>] = []

    let applyCancellable = CancellableCallStore()
    let familiesCancellable = CancellableCallStore()
    let reservedCancellable = CancellableCallStore()
    let requiredBalanceCancellable = CancellableCallStore()
    let terminateCancellable = CancellableCallStore()

    private var shouldStopTattooApplyActivity: Bool = false

    init(
        selectedWallet: WalletManaging,
        chain: ChainModel,
        connection: ChainConnection,
        runtimeProvider: RuntimeProviderProtocol,
        flowState: ProofOfInkFlowStateProtocol,
        proofOfInkFactory: ProofOfInkOperationFactoryProtocol,
        jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol,
        requiredBalanceFactory: ProofOfInkBalanceFactoryProtocol,
        operationQueue: OperationQueue,
        tattooTerminationService: TattooTerminateServicing,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.selectedWallet = selectedWallet
        self.chain = chain
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.flowState = flowState
        self.proofOfInkFactory = proofOfInkFactory
        self.jsonLocalSubscriptionFactory = jsonLocalSubscriptionFactory
        self.requiredBalanceFactory = requiredBalanceFactory
        self.operationQueue = operationQueue
        self.tattooTerminationService = tattooTerminationService
        self.logger = logger
    }

    deinit {
        familiesCancellable.cancel()
        reservedCancellable.cancel()
        requiredBalanceCancellable.cancel()
        #if TESTNET_FEATURE
            topUpTask?.cancel()
        #endif
    }

    private func provideRequiredBalance() {
        let wrapper = requiredBalanceFactory.flowRequiredBalanceWrapper(
            for: selectedWallet,
            chain: chain,
            connection: connection,
            runtimeProvider: runtimeProvider
        )

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: requiredBalanceCancellable,
            runningCallbackIn: .main
        ) { [weak self] result in
            MainActor.assumeIsolated {
                switch result {
                case let .success(amount):
                    self?.presenter?.didReceiveRequiredPersonBalance(amount)
                case let .failure(error):
                    self?.presenter?.didReceiveError(.requiredPersonBalance(error))
                }
            }
        }
    }

    private func subscribeRemoteState() {
        guard
            let store = try? flowState.setupTattooSelectionSyncService(
                for: selectedWallet,
                chain: chain
            ) else {
            return
        }

        store.add(
            observer: self,
            queue: .main
        ) { [weak self] _, newState in
            guard let newState else {
                return
            }

            self?.handle(remoteState: newState)
        }
    }

    private func handle(remoteState: TattooSelectionState) {
        MainActor.assumeIsolated {
            if shouldStopTattooApplyActivity, remoteState.candidate != nil {
                shouldStopTattooApplyActivity = false
                presenter?.didReceive(tattooApplyActivity: false)
            }

            presenter?.didReceiveNextPersonalId(remoteState.personalId)
            presenter?.didReceiveCandidate(remoteState.candidate)
            presenter?.didReceiveCurrentBalance(remoteState.account?.data.available)

            #if TESTNET_FEATURE
                if topUpTask != nil {
                    presenter?.didReceiveTopUp(inProgress: false)
                }
            #endif
        }
    }

    private func provideDesignFamilies() {
        familiesCancellable.cancel()

        let wrapper = proofOfInkFactory.fetchAllFamilies(
            for: connection,
            runtimeProvider: runtimeProvider
        )

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: familiesCancellable,
            runningCallbackIn: .main
        ) { [weak self] result in
            MainActor.assumeIsolated {
                switch result {
                case let .success(families):
                    self?.presenter?.didReceiveDesignFamilies(families)
                case let .failure(error):
                    self?.presenter?.didReceiveError(.designFamiliesFailed(error))
                }
            }
        }
    }

    private func provideReservedDesigns() {
        reservedCancellable.cancel()

        let wrapper = proofOfInkFactory.fetchReservedDesignes(
            for: connection,
            runtimeProvider: runtimeProvider
        )

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: reservedCancellable,
            runningCallbackIn: .main
        ) { [weak self] result in
            MainActor.assumeIsolated {
                switch result {
                case let .success(reservedItems):
                    self?.presenter?.didReceiveReservedDesigns(reservedItems)
                case let .failure(error):
                    self?.presenter?.didReceiveError(.reservedFailed(error))
                }
            }
        }
    }
}

extension TattooListInteractor: TattooListInteractorInputProtocol {
    func setup() {
        provideDesignFamilies()
        provideReservedDesigns()
        subscribeRemoteState()
        provideRequiredBalance()
    }

    func applyForTattoo() {
        guard !applyCancellable.hasCall else { return }
        guard let operationFactory = try? flowState.applyOperationFactory(for: selectedWallet, chain: chain) else {
            return
        }

        MainActor.assumeIsolated {
            presenter?.didReceive(tattooApplyActivity: true)
            shouldStopTattooApplyActivity = false
        }

        let wrapper = CompoundOperationWrapper(targetOperation: operationFactory.createApplyOperation())
        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: applyCancellable,
            runningCallbackIn: .main
        ) { [weak self] result in
            MainActor.assumeIsolated {
                switch result {
                case .success:
                    // result handled by observing candidate state in handle(remoteState:)
                    // stop activity only when candidate appears
                    self?.shouldStopTattooApplyActivity = true
                case let .failure(error):
                    self?.presenter?.didReceive(tattooApplyActivity: false)
                    self?.presenter?.didReceiveGeneralError(error)
                }
            }
        }
    }

    func retryFamilies() {
        provideDesignFamilies()
    }

    func retryReserved() {
        if !reservedCancellable.hasCall {
            provideReservedDesigns()
        }
    }

    func retryTattooMetadata(for familyIds: [ProofOfInkPallet.FamilyId]) {
        subscribeTattooMetadata(for: familyIds)
    }

    func subscribeTattooMetadata(for familyIds: [ProofOfInkPallet.FamilyId]) {
        tattooMetadataProviders.forEach { $0.removeObserver(self) }

        tattooMetadataProviders = subscribeToTattooMetadata(for: familyIds)
    }

    func retryRequiredPersonBalance() {
        provideRequiredBalance()
    }

    func exitTattoo() {
//        determineStateObserver.didExitDIM()
    }

    func terminateProofOfInk() {
        guard !terminateCancellable.hasCall else { return }

        MainActor.assumeIsolated {
            presenter?.didReceiveTermination(inProgress: true)
        }

        let wrapper = tattooTerminationService.flakeOut()
        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: terminateCancellable,
            runningCallbackIn: .main
        ) { [weak self] result in
            MainActor.assumeIsolated {
                self?.presenter?.didReceiveTermination(inProgress: false)
                switch result {
                case .success:
                    break
//                    self?.determineStateObserver.didExitDIM()
                case let .failure(error):
                    self?.presenter?.didReceiveGeneralError(error)
                }
            }
        }
    }

    #if TESTNET_FEATURE
        func addDeposit(amount: Balance) {
            guard let topUpService else {
                return
            }
            MainActor.assumeIsolated {
                presenter?.didReceiveTopUp(inProgress: true)
            }

            topUpTask?.cancel()
            topUpTask = Task { @MainActor [weak presenter, logger, selectedWallet] in
                do {
                    try await topUpService.topUp(
                        selectedWallet,
                        amount: .plank(amount)
                    )
                    // didReceiveTopUp(inProgress: false) will be handled by update balance handler
                } catch {
                    logger.error("Top up failed: \(error)")
                    presenter?.didReceiveTopUp(inProgress: false)
                    presenter?.didReceiveGeneralError(error)
                }
            }
        }
    #endif
}

extension TattooListInteractor: TattooMetadataLocalSubscriptionHandler, TattooMetadataLocalStorageSubscriber {
    func handleTattooMetadata(result: Result<TattooMetadata, Error>, familyId: ProofOfInkPallet.FamilyId) {
        MainActor.assumeIsolated {
            switch result {
            case let .success(metadata):
                presenter?.didReceiveTattooMetadata(metadata, for: familyId)
            case let .failure(error):
                presenter?.didReceiveError(.tattooMetadataFailed(error))
            }
        }
    }
}
