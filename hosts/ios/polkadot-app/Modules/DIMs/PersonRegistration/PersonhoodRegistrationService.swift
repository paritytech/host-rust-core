import Foundation
import os
import ExtrinsicService
import SubstrateSdk
import Operation_iOS
import BandersnatchApi
import Keystore_iOS
import CommonService
import KeyDerivation
import SubstrateOperation
import ChainRegistry

protocol PersonhoodRegistrationServicing: ApplicationServiceProtocol,
    PersonSelfIncludeBackgroundServiceDelegate,
    PersonhoodRegistrationSyncObserver,
    AnyObject {
    var stateObserver: PersonhoodRegistrationStateObserving? { get set }

    var localState: PersonRegistration.LocalState { get }
    var remoteState: PersonRegistration.RemoteState? { get }

    func triggerRegistration()
}

protocol PersonhoodRegistrationStateObserving: AnyObject {
    func registrationService(
        _ service: PersonhoodRegistrationServicing,
        didUpdate localState: PersonRegistration.LocalState
    )

    func registrationService(
        _ service: PersonhoodRegistrationServicing,
        didUpdate remoteState: PersonRegistration.RemoteState
    )
}

// @unchecked Sendable: all mutable state confined to serial workQueue
final class PersonhoodRegistrationService: @unchecked Sendable {
    let chain: ChainProtocol
    let candidateWallet: WalletManaging
    let mobRuleWallet: WalletManaging
    let scoreWallet: WalletManaging
    let resourcesWallet: WalletManaging
    let vrfManager: BandersnatchKeyManaging
    let blockNumberOperationFactory: BlockNumberOperationFactoryProtocol
    let operationFactory: PersonhoodRegistrationOperationMaking
    let selfIncludeSubmissionService: SelfIncludeSubmitting
    let extrinsicSubmissionFacade: ExtrinsicSubmissionMonitorFacadeProtocol
    let candidateOriginFactory: CandidateOriginFactoryProtocol
    let personhoodOriginFactory: PersonhoodOriginFactoryProtocol
    let chainRegistry: ChainRegistryProtocol
    let syncQueue: DispatchQueue
    let logger: LoggerProtocol
    let operationQueue: OperationQueue

    weak var stateObserver: PersonhoodRegistrationStateObserving? {
        didSet {
            if stateObserver != nil {
                reportInitialState()
            }
        }
    }

    private(set) var localState = PersonRegistration.LocalState(progress: .notTriggered, error: nil) {
        didSet { performReportLocalState() }
    }

    private(set) var remoteState: PersonRegistration.RemoteState? {
        didSet { performReportRemoteState() }
    }

    private(set) var extrinsicSubmissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol?

    init(
        chain: ChainProtocol,
        candidateWallet: WalletManaging,
        mobRuleWallet: WalletManaging,
        scoreWallet: WalletManaging,
        resourcesWallet: WalletManaging,
        vrfManager: BandersnatchKeyManaging,
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        blockNumberOperationFactory: BlockNumberOperationFactoryProtocol,
        operationFactory: PersonhoodRegistrationOperationMaking,
        extrinsicSubmissionFacade: ExtrinsicSubmissionMonitorFacadeProtocol = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        ),
        candidateOriginFactory: CandidateOriginFactoryProtocol,
        personhoodOriginFactory: PersonhoodOriginFactoryProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        syncQueue: DispatchQueue = DispatchQueue(label: "io.polkadot.app.person.register.\(UUID().uuidString)"),
        logger: LoggerProtocol = Logger.shared,
        selfIncludeSubmissionService: SelfIncludeSubmitting
    ) {
        self.chain = chain
        self.candidateWallet = candidateWallet
        self.mobRuleWallet = mobRuleWallet
        self.scoreWallet = scoreWallet
        self.resourcesWallet = resourcesWallet
        self.vrfManager = vrfManager
        self.blockNumberOperationFactory = blockNumberOperationFactory
        self.operationFactory = operationFactory
        self.selfIncludeSubmissionService = selfIncludeSubmissionService
        self.chainRegistry = chainRegistry
        self.extrinsicSubmissionFacade = extrinsicSubmissionFacade
        self.candidateOriginFactory = candidateOriginFactory
        self.personhoodOriginFactory = personhoodOriginFactory
        self.operationQueue = operationQueue
        self.syncQueue = syncQueue
        self.logger = logger
    }

    func setupExtrinsicSubmissionMonitor() -> ExtrinsicSubmitMonitorFactoryProtocol? {
        if let extrinsicSubmissionMonitor {
            return extrinsicSubmissionMonitor
        }

        do {
            let monitor = try extrinsicSubmissionFacade.createMonitorFactory(chain: chain)

            extrinsicSubmissionMonitor = monitor

            return monitor
        } catch {
            logger.error("Can't create extrinsic monitor: \(error)")

            return nil
        }
    }

    func updateLocalState(error: PersonRegistration.LocalState.Error?) {
        setLocalState(localState.changing(error: error))
    }

    func updateLocalState(progress: PersonRegistration.Progress) {
        setLocalState(localState.changing(progress: progress))
    }

    func resetLocalStateIfError() {
        guard let error = localState.error else {
            return
        }
        switch error {
        case .failedPersonRegistration,
             .failedCreatingAlias,
             .failedSettingPersonalIdAccount,
             .failedSelfInclude:
            setLocalState(.init(progress: .idle, error: nil))
        }
    }
}

extension PersonhoodRegistrationService: PersonhoodRegistrationServicing {
    func setup() {
        applyState()
    }

    func throttle() {}

    func triggerRegistration() {
        syncQueue.async { [weak self] in
            guard
                let self,
                localState.progress.isNotTriggered
            else {
                return
            }
            localState = localState.changing(progress: .idle)
            applyState()
        }
    }
}

extension PersonhoodRegistrationService: PersonhoodRegistrationSyncObserver {
    func personhoodRegistrationSyncChanged(by change: PersonhoodRegistrationSyncChange) {
        syncQueue.async { [weak self] in
            guard let self else {
                return
            }

            if let remoteState {
                self.remoteState = remoteState.applyingChange(change)
            } else {
                initializeRemoteStateIfPossible(with: change)
            }

            applyState()
        }
    }
}

private extension PersonhoodRegistrationService {
    func initializeRemoteStateIfPossible(with change: PersonhoodRegistrationSyncChange) {
        guard
            case let .defined(proofOfInkCandidate) = change.proofOfInkCandidate,
            case let .defined(gameCandidate) = change.gameCandidate,
            case let .defined(mobRuleAlias) = change.mobRuleAlias,
            case let .defined(scoreAlias) = change.scoreAlias,
            case let .defined(resourcesAlias) = change.resourcesAlias,
            case let .defined(personalId) = change.personalId
        else {
            logger.warning("Change doesn't include all the data: \(change)")
            return
        }

        remoteState = .init(
            proofOfInkCandidate: proofOfInkCandidate,
            gameCandidate: gameCandidate,
            personalId: personalId,
            mobRuleAlias: mobRuleAlias,
            scoreAlias: scoreAlias,
            resourcesAlias: resourcesAlias,
            personRecord: change.personRecord.value ?? nil,
            memberRingPosition: change.memberRingPosition.value ?? nil,
            keysStatus: change.keysStatus.value ?? nil,
            bestBlockTimestampMs: change.bestBlockTimestampMs.valueWhenDefined(else: nil),
            collectionInfo: change.collectionInfo.valueWhenDefined(else: nil),
            ringsState: change.ringsState.valueWhenDefined(else: nil),
            blockHash: change.blockHash
        )
    }

    func reportInitialState() {
        syncQueue.async { [weak self] in
            guard let self else {
                return
            }
            performReportLocalState()
            performReportRemoteState()
        }
    }

    func performReportLocalState() {
        stateObserver?.registrationService(
            self,
            didUpdate: localState
        )
    }

    func performReportRemoteState() {
        if let remoteState {
            stateObserver?.registrationService(
                self,
                didUpdate: remoteState
            )
        }
    }

    func setLocalState(_ newValue: PersonRegistration.LocalState) {
        syncQueue.async { [weak self] in
            self?.localState = newValue
            self?.applyState()
        }
    }
}
