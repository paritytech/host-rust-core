import Foundation
import CommonService
import ExtrinsicService
import Operation_iOS
import Individuality
import KeyDerivation
import ChainRegistry

protocol MobRuleCreditClaimServicing: ApplicationServiceProtocol {}

final class MobRuleCreditClaimService {
    private let chain: ChainModel
    private let selectedWallet: WalletManaging
    private let trackingService: any MobRulePointsTrackingServicing
    private let extrinsicSubmissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol
    private let extrinsicOriginFactory: PersonhoodOriginFactoryProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    private let workingQueue: DispatchQueue

    private var callStore = CancellableCallStore()
    private var isActive: Bool = false

    init(
        chain: ChainModel,
        selectedWallet: WalletManaging,
        trackingService: any MobRulePointsTrackingServicing,
        extrinsicSubmissionMonitor: ExtrinsicSubmitMonitorFactoryProtocol,
        extrinsicOriginFactory: PersonhoodOriginFactoryProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chain = chain
        self.selectedWallet = selectedWallet
        self.trackingService = trackingService
        self.extrinsicSubmissionMonitor = extrinsicSubmissionMonitor
        self.extrinsicOriginFactory = extrinsicOriginFactory
        self.operationQueue = operationQueue
        self.logger = logger

        workingQueue = DispatchQueue(label: "io.polkadot.mobrule.creditclaim.\(UUID().uuidString)")
    }
}

private extension MobRuleCreditClaimService {
    func claimPointsIfNeeded(for state: MobRulePointsTracking.State) {
        guard let claimablePoints = state.points.claimable, claimablePoints > 0 else {
            logger.debug("No points to claim")
            return
        }

        guard !callStore.hasCall else {
            logger.warning("Already claiming points")
            return
        }

        logger.debug("Claiming mob rule points: \(claimablePoints)")

        do {
            let origin = try extrinsicOriginFactory.createAsPersonalAliasWithAccount(
                input: .init(
                    wallet: selectedWallet,
                    chain: chain,
                    context: Data(PalletContext.mobRule.utf8),
                    blockHash: nil
                )
            )

            let wrapper = extrinsicSubmissionMonitor.submitAndMonitorWrapper(
                extrinsicBuilderClosure: { builder in
                    try builder.adding(call: MobRulePallet.ClaimCreditCall.runtimeCall())
                },
                origin: origin,
                params: ExtrinsicSubmissionParams(feeAssetId: nil, eventsMatcher: nil)
            )

            executeCancellable(
                wrapper: wrapper,
                inOperationQueue: operationQueue,
                backingCallIn: callStore,
                runningCallbackIn: workingQueue
            ) { [weak self] result in
                do {
                    let submissionResult = try result.get()
                    switch submissionResult.status {
                    case .success:
                        self?.logger.debug("Successfully claimed credits")
                    case let .failure(failedExtrinsic):
                        self?.logger.error("Credits claiming failed: \(failedExtrinsic)")
                    }
                } catch {
                    self?.logger.error("Credits claiming failed: \(error)")
                }
            }
        } catch {
            logger.error("Unexpected claim error: \(error)")
        }
    }

    func startPointsTracking() {
        trackingService.add(
            observer: self,
            sendStateOnSubscription: true,
            queue: workingQueue
        ) { [weak self] _, newState in
            guard let newState else {
                return
            }

            self?.claimPointsIfNeeded(for: newState)
        }
    }

    func stopPointsTracking() {
        trackingService.remove(observer: self)
    }
}

extension MobRuleCreditClaimService: MobRuleCreditClaimServicing {
    func setup() {
        workingQueue.async {
            guard !self.isActive else {
                return
            }

            self.startPointsTracking()
        }
    }

    func throttle() {
        workingQueue.async {
            guard self.isActive else {
                return
            }

            self.stopPointsTracking()
        }
    }
}
