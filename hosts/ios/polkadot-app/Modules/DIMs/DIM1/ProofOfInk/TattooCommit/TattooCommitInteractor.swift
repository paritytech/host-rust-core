import BulletinChain
import Foundation
import Operation_iOS
import SubstrateSdk
import ExtrinsicService
import OperationExt
import Individuality
import KeyDerivation
import ChainRegistry

final class TattooCommitInteractor: AnyProviderAutoCleaning, RuntimeConstantFetching {
    weak var presenter: TattooCommitInteractorOutputProtocol?

    let peopleChain: ChainModel
    let bulletinChain: ChainModel

    let choice: ProofOfInk.Choice
    let proofOfInkState: ProofOfInkFlowStateProtocol
    let selectedWallet: WalletManaging
    let extrinsicSubmissionFactory: ExtrinsicSubmitMonitorFactoryProtocol
    let extrinsicOrigin: ExtrinsicOriginDefining
    let peopleConnection: ChainConnection
    let peopleRuntimeProvider: RuntimeProviderProtocol
    let bulletinRuntimeProvider: RuntimeProviderProtocol
    let operationQueue: OperationQueue
    let commitAvailabilityService: TattooCommitAvailabilityServicing
    let logger: LoggerProtocol
    let jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol

    private var tattooMetadataProvider: AnySingleValueProvider<TattooMetadata>?

    var systemLocalDataFactory: SystemLocalDataFactoryProtocol {
        proofOfInkState.systemLocalDataFactory
    }

    private var blockNumberProvider: AnyDataProvider<SystemLocalData.DecodedBlockNumber>?

    private let blockTimeCancellable = CancellableCallStore()

    private(set) var extrinsicCancellable = CancellableCallStore()

    private var commitAvailabilityTask: Task<Void, Never>?

    init(
        choice: ProofOfInk.Choice,
        peopleChain: ChainModel,
        peopleConnection: ChainConnection,
        peopleRuntimeProvider: RuntimeProviderProtocol,
        bulletinChain: ChainModel,
        bulletinRuntimeProvider: RuntimeProviderProtocol,
        proofOfInkState: ProofOfInkFlowStateProtocol,
        commitAvailabilityService: TattooCommitAvailabilityServicing,
        selectedWallet: WalletManaging,
        extrinsicSubmissionFactory: ExtrinsicSubmitMonitorFactoryProtocol,
        extrinsicOrigin: ExtrinsicOriginDefining,
        operationQueue: OperationQueue,
        jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.choice = choice
        self.peopleChain = peopleChain
        self.peopleConnection = peopleConnection
        self.peopleRuntimeProvider = peopleRuntimeProvider
        self.bulletinChain = bulletinChain
        self.bulletinRuntimeProvider = bulletinRuntimeProvider
        self.proofOfInkState = proofOfInkState
        self.selectedWallet = selectedWallet
        self.extrinsicSubmissionFactory = extrinsicSubmissionFactory
        self.extrinsicOrigin = extrinsicOrigin
        self.operationQueue = operationQueue
        self.jsonLocalSubscriptionFactory = jsonLocalSubscriptionFactory
        self.logger = logger
        self.commitAvailabilityService = commitAvailabilityService
    }

    deinit {
        blockTimeCancellable.cancel()
        extrinsicCancellable.cancel()
        commitAvailabilityTask?.cancel()
    }

    private func createBlockNumberProvider() {
        clear(dataProvider: &blockNumberProvider)

        do {
            try proofOfInkState.setupBlockTimeService(for: bulletinChain.chainId)

            blockNumberProvider = subscribeToBlockNumber(for: bulletinChain.chainId)
        } catch {
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .blockTimeServiceError(error))
            }
        }
    }

    private func provideBulletinBlockTime() {
        do {
            let blockTimeService = try proofOfInkState.setupBlockTimeService(for: bulletinChain.chainId)

            let wrapper = try proofOfInkState.getBlockTimeOperationFactory(
                for: bulletinChain.chainId
            )
            .createBlockTimeOperation(
                from: peopleRuntimeProvider,
                blockTimeEstimationService: blockTimeService
            )

            executeCancellable(
                wrapper: wrapper,
                inOperationQueue: operationQueue,
                backingCallIn: blockTimeCancellable,
                runningCallbackIn: .main
            ) { [weak self] result in
                MainActor.assumeIsolated {
                    switch result {
                    case let .success(blockTime):
                        self?.presenter?.didReceive(blockTime: blockTime)
                    case let .failure(error):
                        self?.presenter?.didReceive(error: .blockTimeServiceError(error))
                    }
                }
            }
        } catch {
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .blockTimeServiceError(error))
            }
        }
    }

    private func provideCommitmentTimeout() {
        fetchConstant(
            for: TransactionStoragePallet.authorizationPeriodPath,
            runtimeCodingService: bulletinRuntimeProvider,
            operationQueue: operationQueue
        ) { [weak self] (result: Result<BlockNumber, Error>) in
            MainActor.assumeIsolated {
                switch result {
                case let .success(period):
                    self?.presenter?.didReceive(commitmentTimeout: period)
                case let .failure(error):
                    self?.presenter?.didReceive(error: .commitmentTimeout(error))
                }
            }
        }
    }

    private func provideJudgementDuration() {
        fetchConstant(
            for: MobRulePallet.minCaseDurationPath,
            runtimeCodingService: peopleRuntimeProvider,
            operationQueue: operationQueue
        ) { [weak self] (result: Result<OnChainHour, Error>) in
            MainActor.assumeIsolated {
                switch result {
                case let .success(duration):
                    self?.presenter?.didReceive(minJudgementDuration: duration)
                case let .failure(error):
                    self?.presenter?.didReceive(error: .judgementDuration(error))
                }
            }
        }

        fetchConstant(
            for: MobRulePallet.maxVotingDurationPath,
            runtimeCodingService: peopleRuntimeProvider,
            operationQueue: operationQueue
        ) { [weak self] (result: Result<OnChainHour, Error>) in
            MainActor.assumeIsolated {
                switch result {
                case let .success(duration):
                    self?.presenter?.didReceive(maxJudgementDuration: duration)
                case let .failure(error):
                    self?.presenter?.didReceive(error: .judgementDuration(error))
                }
            }
        }
    }

    private func subscribeData() {
        createBlockNumberProvider()
    }

    private func subscribeTattooMetadata() {
        tattooMetadataProvider?.removeObserver(self)

        tattooMetadataProvider = subscribeToTattooMetadata(for: choice.familyId)
    }

    private func submit(choice: ProofOfInk.Choice, personalId: ProofOfInkPallet.PersonalId?) {
        guard !extrinsicCancellable.hasCall else {
            return
        }

        let builderClosure: ExtrinsicBuilderClosure = { builder in
            try builder.adding(call: ProofOfInkPallet.CommitCall(
                choice: choice.toRemote(),
                requireId: personalId
            )
            .runtimeCall())
        }

        let wrapper = extrinsicSubmissionFactory.submitAndMonitorWrapper(
            extrinsicBuilderClosure: builderClosure,
            origin: extrinsicOrigin,
            params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
        )

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: extrinsicCancellable,
            runningCallbackIn: .main
        ) { [weak self] result in
            MainActor.assumeIsolated {
                switch result {
                case let .success(commitResult):
                    self?.handleCommit(result: commitResult.status)
                case let .failure(error):
                    self?.presenter?.didReceive(error: .confirmationFailed(error))
                }
            }
        }
    }

    private func handleCommit(result: SubstrateExtrinsicStatus) {
        switch result {
        case let .success(extrinsicHash):
            MainActor.assumeIsolated {
                presenter?.didConfirm(with: extrinsicHash.extrinsicHash)
            }
        case let .failure(failure):
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .confirmationFailed(failure.error))
            }
        }
    }
}

extension TattooCommitInteractor: TattooCommitInteractorInputProtocol {
    func setup() {
        subscribeData()
        provideCommitmentTimeout()
        provideJudgementDuration()

        subscribeTattooMetadata()
    }

    func retrySubscription() {
        subscribeData()
    }

    func retryCommitmentTimeout() {
        provideCommitmentTimeout()
    }

    func retryJudgementDuration() {
        provideJudgementDuration()
    }

    func retryTattooMetadata() {
        subscribeTattooMetadata()
    }

    func confirm() {
        let personalId: ProofOfInkPallet.PersonalId? =
            if case let .proceduralPersonal(model) = choice {
                model.personalId
            } else {
                nil
            }

        commitAvailabilityTask?.cancel()
        commitAvailabilityTask = Task { [weak self] in
            do {
                try await self?.commitAvailabilityService.checkAvailability()

                Task { @MainActor in
                    guard let self else { return }
                    self.submit(choice: self.choice, personalId: personalId)
                }
            } catch {
                Task { @MainActor in
                    guard let self else { return }
                    self.presenter?.didReceive(error: .commitAvailabilityFailed(error))
                }
            }
        }
    }
}

extension TattooCommitInteractor: SystemLocalDataSubscriber, SystemLocalDataHandler {
    func handleBlockNumber(result: Result<BlockNumber?, Error>, chainId: ChainModel.Id) {
        switch result {
        case let .success(blockNumber):
            guard blockNumber != nil else {
                return
            }

            if chainId == bulletinChain.chainId {
                provideBulletinBlockTime()
            }
        case let .failure(error):
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .blockTimeServiceError(error))
            }
        }
    }
}

extension TattooCommitInteractor: TattooMetadataLocalSubscriptionHandler, TattooMetadataLocalStorageSubscriber {
    func handleTattooMetadata(
        result: Result<TattooMetadata, Error>,
        familyId _: ProofOfInkPallet.FamilyId
    ) {
        switch result {
        case let .success(metadata):
            MainActor.assumeIsolated {
                presenter?.didReceiveTattoo(metadata: metadata)
            }
        case let .failure(error):
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .tattooMetadataFailed(error))
            }
        }
    }
}
