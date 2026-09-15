import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import Operation_iOS
import CommonService
import Individuality
import ChainRegistry

protocol MobRulePointsTrackingServicing: ApplicationServiceProtocol & BaseObservableStateStoreProtocol
    where RemoteState == MobRulePointsTracking.State {}

final class MobRulePointsTrackingService: BaseObservableStateStore<MobRulePointsTracking.State> {
    let mobRuleAlias: PeoplePallet.ContextualAlias
    let chainId: ChainModel.Id
    let chainRegistry: ChainRegistryProtocol
    let operationQueue: OperationQueue
    let workingQueue: DispatchQueue

    private var payoutState: MobRulePointsTracking.PayoutState?
    private var payoutSubscription: CallbackBatchStorageSubscription<MobRulePointsTracking.PayoutStateChange>?
    private var pointsSubscription: CallbackBatchStorageSubscription<MobRulePointsTracking.PointsStateChange>?

    init(
        chainId: ChainModel.Id,
        mobRuleAlias: PeoplePallet.ContextualAlias,
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chainId = chainId
        self.mobRuleAlias = mobRuleAlias
        self.operationQueue = operationQueue
        self.chainRegistry = chainRegistry

        workingQueue = DispatchQueue(label: "io.web3citizenship.mobrule.pointstracking.\(UUID().uuidString)")

        super.init(logger: logger)
    }
}

private extension MobRulePointsTrackingService {
    func apply(payoutChanges: MobRulePointsTracking.PayoutStateChange) {
        let oldState = payoutState

        if let oldState {
            payoutState = oldState.applying(payoutChanges)
        } else {
            guard
                payoutChanges.creditDistribution.isDefined,
                payoutChanges.roundSchedules.isDefined else {
                logger.error("Expected defined changes: \(payoutChanges)")
                return
            }

            payoutState = MobRulePointsTracking.PayoutState(
                creditDistribution: payoutChanges.creditDistribution.valueWhenDefined(else: nil),
                roundSchedules: payoutChanges.roundSchedules.valueWhenDefined(else: nil),
                blockHash: payoutChanges.blockHash
            )
        }

        guard let payoutState else {
            logger.error("Unexpected missing payout state")
            return
        }

        guard oldState != payoutState else {
            logger.debug("No payout changes")
            return
        }

        if oldState?.currentRound != payoutState.currentRound {
            subscribeToPoints(for: mobRuleAlias.alias)
        } else if payoutState.currentRound == nil {
            setupNoPointsState(for: payoutState)
        } else if let state = stateObservable.state {
            stateObservable.state = MobRulePointsTracking.State(
                payout: payoutState,
                points: state.points,
                blockHash: payoutChanges.blockHash
            )
        }
    }

    func apply(pointsChanges: MobRulePointsTracking.PointsStateChange) {
        guard let payoutState else {
            return
        }

        if let state = stateObservable.state, payoutState == state.payout {
            stateObservable.state = state.applying(pointsChanges)
        } else {
            guard
                pointsChanges.claimable.isDefined,
                pointsChanges.pending.isDefined else {
                logger.error("Expected defined changes: \(pointsChanges)")
                return
            }

            let pointsState = MobRulePointsTracking.PointsState(
                claimable: pointsChanges.claimable.valueWhenDefined(else: nil),
                pending: pointsChanges.pending.valueWhenDefined(else: nil)
            )

            stateObservable.state = MobRulePointsTracking.State(
                payout: payoutState,
                points: pointsState,
                blockHash: pointsChanges.blockHash
            )
        }

        logger.debug("Did update state: \(String(describing: stateObservable.state))")
    }

    func subscribeToPayoutState() {
        do {
            let connection = try chainRegistry.getConnectionOrError(for: chainId)
            let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)

            payoutSubscription = CallbackBatchStorageSubscription(
                requests: [
                    BatchStorageSubscriptionRequest(
                        innerRequest: UnkeyedSubscriptionRequest(
                            storagePath: MobRulePallet.payoutDistributionPath,
                            localKey: ""
                        ),
                        mappingKey: MobRulePointsTracking.PayoutStateChange.Key.creditDistribution.rawValue
                    ),

                    BatchStorageSubscriptionRequest(
                        innerRequest: UnkeyedSubscriptionRequest(
                            storagePath: MobRulePallet.roundSchedulesPath,
                            localKey: ""
                        ),
                        mappingKey: MobRulePointsTracking.PayoutStateChange.Key.roundSchedule.rawValue
                    )
                ],
                connection: connection,
                runtimeService: runtimeProvider,
                repository: nil,
                operationQueue: operationQueue,
                callbackQueue: workingQueue
            ) { [weak self] result in
                self?.mutex.lock()

                defer {
                    self?.mutex.unlock()
                }

                switch result {
                case let .success(changes):
                    self?.apply(payoutChanges: changes)
                case let .failure(error):
                    self?.logger.error("Unexpected payout distribution error: \(error)")
                }
            }

            payoutSubscription?.subscribe()

            logger.debug("Subscribed payouts")
        } catch {
            logger.error("Can't subscribe payout distribution: \(error)")
        }
    }

    func setupNoPointsState(for payoutState: MobRulePointsTracking.PayoutState) {
        stateObservable.state = MobRulePointsTracking.State(
            payout: payoutState,
            points: .init(claimable: nil, pending: nil),
            blockHash: payoutState.blockHash
        )
    }

    func createPointsSubscriptionRequest(
        for currentRound: MobRulePallet.RoundIndex,
        alias: PeoplePallet.Alias,
        isClaimable: Bool
    ) -> BatchStorageSubscriptionRequest {
        let targetRound = isClaimable ? currentRound : currentRound + 1
        let mappingKey: MobRulePointsTracking.PointsStateChange.Key = isClaimable ? .claimable : .pending

        return BatchStorageSubscriptionRequest(
            innerRequest: DoubleMapSubscriptionRequest(
                storagePath: MobRulePallet.votingPoints,
                localKey: "",
                keyParamClosure: {
                    (StringScaleMapper(value: targetRound), BytesCodable(wrappedValue: alias))
                }
            ),
            mappingKey: mappingKey.rawValue
        )
    }

    func subscribeToPoints(for alias: PeoplePallet.Alias) {
        clearPointsSubscription()

        guard let payoutState else {
            return
        }

        guard let round = payoutState.currentRound else {
            logger.debug("No payout distribution")
            setupNoPointsState(for: payoutState)
            return
        }

        do {
            let connection = try chainRegistry.getConnectionOrError(for: chainId)
            let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)

            pointsSubscription = CallbackBatchStorageSubscription(
                requests: [
                    createPointsSubscriptionRequest(for: round, alias: alias, isClaimable: true),
                    createPointsSubscriptionRequest(for: round, alias: alias, isClaimable: false)
                ],
                connection: connection,
                runtimeService: runtimeProvider,
                repository: nil,
                operationQueue: operationQueue,
                callbackQueue: workingQueue
            ) { [weak self] result in
                self?.mutex.lock()

                defer {
                    self?.mutex.unlock()
                }

                switch result {
                case let .success(pointsChanges):
                    self?.apply(pointsChanges: pointsChanges)
                case let .failure(error):
                    self?.logger.error("Unexpected points subscription error: \(error)")
                }
            }

            pointsSubscription?.subscribe()

            logger.debug("Subscribed points for payout: \(payoutState)")
        } catch {
            logger.error("Can't subscribe points: \(error)")
        }
    }

    func clearPointsSubscription() {
        pointsSubscription?.unsubscribe()
        pointsSubscription = nil
    }

    func clearPayoutSubscription() {
        payoutSubscription?.unsubscribe()
        payoutSubscription = nil
    }
}

extension MobRulePointsTrackingService: MobRulePointsTrackingServicing {
    func setup() {
        workingQueue.async {
            self.mutex.lock()

            defer {
                self.mutex.unlock()
            }

            guard self.payoutSubscription == nil else {
                return
            }

            self.subscribeToPayoutState()
        }
    }

    func throttle() {
        workingQueue.async {
            self.mutex.lock()

            defer {
                self.mutex.unlock()
            }

            self.clearPayoutSubscription()
            self.clearPointsSubscription()
        }
    }
}
